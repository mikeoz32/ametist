require "fiber"
require "log"
require "./queue"

require "./movie/behavior"
require "./movie/mailbox"
require "./movie/context"
require "./movie/system"
require "./movie/future"
require "./movie/ask"
require "./movie/streams"

module Movie
  # Movie is an actor framework for Crystal
  # It is possible to build actors due to experimental execution contexts in language
  # Will hope that Crystal will not be deprecated in future
  #
  # Each actor is represented by its behavior, which is a class that defines the actor's state and behavior.
  # Internally actors are instances of ActorContext.
  # Actors could be referenced with their ActorRef.
  # Actors communicate with each other by sending messages.
  # Each actor has a mailbox where messages are queued and processed. Mailboxes are dispatched by dispatchers.
  # Dispatchers are responsible for scheduling mailboxes to be executed in specific execution context.
  #
  # TODO: implement envelopes for messages to handle metadata and priority?. (sender, priority, time_sent, time_received)

  class PoolExecutionContext < Fiber::ExecutionContext::Parallel
  end

  abstract class Dispatcher
    def initialize(execution_context : Fiber::ExecutionContext)
      @execution_context = execution_context
    end

    def dispatch(mailbox : Mailbox)
      @execution_context.spawn do
        mailbox.dispatch
      end
    end
  end

  class PinnedDispatcher < Dispatcher
    # Uses isolated execution context, so only one actor can be executed in by this dispatcher
    # in single thread
    def initialize()
      super(Fiber::ExecutionContext::Isolated.new)
    end
  end

  class ParallelDispatcher < Dispatcher
    # uses parallel execution context, so multiple actors can be executed in parallel in different threads
    def initialize()
      super(Fiber::ExecutionContext::Parallel.new "pd-1", 24)
    end
  end

  class ConcurrentDispatcher < Dispatcher
    # uses concurrent execution context, so multiple actors can be executed concurrently in single thread
    def initialize()
      super(Fiber::ExecutionContext::Concurrent.new)
    end
  end


  abstract class ActorRefBase
    @id : Int32
    getter id : Int32

    def initialize(id : Int32)
      @id = id
    end

    abstract def send_system(message : SystemMessage)
  end

  class ActorRef(T) < ActorRefBase
    def initialize(@system : AbstractActorSystem)
      super(@system.next_id())
    end

    def <<(message : T)
      tell_from(nil, message)
    end

    def tell_from(sender : ActorRefBase?, message : T)
      context = @system.context @id
      raise "Context not found" if context.nil?
      context.as(ActorContext(T)).deliver(message, sender)
    end

    def send_system(message : SystemMessage)
      context = @system.context @id
      raise "Context not found" if context.nil?
      context.as(ActorContext(T)).send_system_message(message)
    end
  end

  struct RootGuardianMessage
  end

  class RootGuardian < AbstractBehavior(RootGuardianMessage)
    def receive(message : RootGuardianMessage)
      puts "RootGuardian received: #{message}"
    end

    def on_signal(signal : SystemMessage)
      puts "RootGuardian received signal: #{signal}"
    end
  end

  struct UserGuardianMessage
  end

  class UserGuardian < AbstractBehavior(UserGuardianMessage)
    def receive(message : UserGuardianMessage)
      puts "UserGuardian received: #{message}"
    end

    def on_signal(signal : Signal)
      puts "UserGuardian received signal: #{signal}"
    end
  end

  struct SystemGuardianMessage
  end

  class SystemGuardian < AbstractBehavior(SystemGuardianMessage)
    def receive(message : SystemGuardianMessage)
      puts "SystemGuardian received: #{message}"
    end

    def on_signal(signal : Signal)
      puts "SystemGuardian received signal: #{signal}"
    end
  end

  class ActorRegistry
    @system : AbstractActorSystem?
    @root : ActorRef(RootGuardianMessage)?
    @user_guardian : ActorRef(UserGuardianMessage)?
    @system_guardian : ActorRef(SystemGuardianMessage)?
    @default_supervision_config : SupervisionConfig = SupervisionConfig.default
    def initialize()
      @actors = {} of Int32 => AbstractActorContext
      @mutex = Mutex.new
    end


    def start
      raise "System not initialized" unless @system

      root_context = create_actor_context(RootGuardian.new, RestartStrategy::RESTART, @default_supervision_config)
      root_ref = root_context.ref
      @root = root_ref

      system_context = create_actor_context(SystemGuardian.new, RestartStrategy::RESTART, @default_supervision_config)
      user_context = create_actor_context(UserGuardian.new, RestartStrategy::RESTART, @default_supervision_config)
      root_context.attach_child system_context.ref
      root_context.attach_child user_context.ref
      @user_guardian = user_context.ref
      @system_guardian = system_context.ref
    end

    protected def create_actor_context(behavior : AbstractBehavior(T), restart_strategy : RestartStrategy = RestartStrategy::RESTART, supervision_config : SupervisionConfig = @default_supervision_config) : ActorContext(T) forall T
      raise "System not initialized" unless @system
      ref = ActorRef(T).new(@system.as(ActorSystem))
      context = ActorContext(T).new(behavior, ref, @system.as(AbstractActorSystem), restart_strategy, supervision_config)
      @mutex.synchronize do
        @actors[ref.id] = context
      end
      context.start
      context
    end

    def system=(system : AbstractActorSystem?) forall T
      @system = system
    end

    def supervision_config=(config : SupervisionConfig)
      @default_supervision_config = config
    end

    def spawn(behavior : AbstractBehavior(T), restart_strategy : RestartStrategy = RestartStrategy::RESTART, supervision_config : SupervisionConfig = @default_supervision_config) : ActorRef(T) forall T
      raise "System not initialized" unless @system
      raise "Root guardian not initialized" if @user_guardian.nil?
      root_context = context(@user_guardian.as(ActorRef(UserGuardianMessage)).id)
      raise "Root context not found" unless root_context
      child = create_actor_context(behavior, restart_strategy, supervision_config)
      root_context.as(ActorContext(UserGuardianMessage)).attach_child(child.ref)
      child.ref
    end

    def context(id : Int32)
      @mutex.synchronize do
        @actors[id]
      end
    end

    def [](id : Int32)
      context(id)
    end
  end

  class DispatcherRegistry
    @@default_dispatcher : Dispatcher?
    @@internal_dispatcher : Dispatcher?

    def initialize
      @dispatchers = {} of String => Dispatcher
    end

    def register(name : String, dispatcher : Dispatcher)
      @dispatchers[name] = dispatcher
    end

    def get(name : String)
      dispatcher = @dispatchers[name]
      dispatcher || raise "Dispatcher not found: #{name}"
      dispatcher
    end

    def default
      # ||= is a safe way to initialize a variable only once
      # if there is no default dispatcher, create one and register it
      # return default or return default = new
      @dispatchers["default"] ||= begin
        @@default_dispatcher ||= ParallelDispatcher.new
      end
    end

    def internal
      @dispatchers["internal"] ||= begin
        @@internal_dispatcher ||= ParallelDispatcher.new
      end
    end
  end

  abstract class AbstractActorSystem
    @id_generator : Atomic(Int32) = Atomic(Int32).new(1)
    @registry : ActorRegistry?

    getter dispatchers : DispatcherRegistry = DispatcherRegistry.new()
    getter mailboxes : MailboxManager = MailboxManager.new()

    def next_id()
      @id_generator.add(1)
    end

    def context(id : Int32)
      @registry.as(ActorRegistry)[id] if @registry
    end
  end

  class ActorSystem(T) < AbstractActorSystem
    @restart_strategy : RestartStrategy = RestartStrategy::RESTART
    @supervision_config : SupervisionConfig = SupervisionConfig.default

    def self.new(main_behavior : AbstractBehavior(T), restart_strategy : RestartStrategy = RestartStrategy::RESTART, supervision_config : SupervisionConfig = SupervisionConfig.default) forall T
      registry = ActorRegistry.new()
      system = ActorSystem(T).allocate
      system.initialize(main_behavior, registry, restart_strategy, supervision_config)
      registry.start
      system.bootstrap_main
      system
    end

    @root : ActorRef(T)?
    @main_behavior : AbstractBehavior(T)?

    protected def initialize(main_behavior : AbstractBehavior(T), registry : ActorRegistry, restart_strategy : RestartStrategy, supervision_config : SupervisionConfig) forall T
      registry.system = self
      registry.supervision_config = supervision_config
      @registry = registry
      @main_behavior = main_behavior
      @restart_strategy = restart_strategy
      @supervision_config = supervision_config
      # @root = registry.spawn(main_behavior)
    end

    protected def bootstrap_main
      behavior = @main_behavior || raise "Main behavior not initialized"
      @root ||= spawn(behavior, @restart_strategy, @supervision_config)
    end


    def <<(message)
      if root = @root
        root << message
      end
    end

    def spawn(behavior : AbstractBehavior(U), restart_strategy : RestartStrategy = RestartStrategy::RESTART, supervision_config : SupervisionConfig = @supervision_config) : ActorRef(U) forall U
      raise "System not initialized" unless @registry
      @registry.as(ActorRegistry).spawn(behavior, restart_strategy, supervision_config)
    end
  end


end

record MainMessage, message : String
