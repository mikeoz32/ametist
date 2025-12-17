require "fiber"
require "./queue"

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

  class Mailbox(T)
    @scheduled = false
    def initialize(@dispatcher : Dispatcher, @context : ActorContext(T))
      @inbox = Queue(T).new
      @mutex = Mutex.new
    end

    def dispatch
        @inbox.dequeue do |message|
          @context.on_message(message) unless message.nil?
        end
        @scheduled = false
        if @inbox.size > 0
          @dispatcher.dispatch(self)
          @scheduled = true
          puts "Resheculing"
        end
    end

    def send(message)
        @inbox.enqueue(message)
        @dispatcher.dispatch(self) unless @scheduled
        @scheduled = true
    end

    def <<(message)
      send(message)
    end
  end

  class MailboxManager
    def create(dispatcher, context)
      Mailbox.new(dispatcher, context)
    end
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


  class DispatcherRegistry
    def initialize
      @dispatchers : Hash(String, Dispatcher) = {} of String => Dispatcher
    end

    def register(name, dispatcher)
      @dispatchers[name] = dispatcher
    end

    def get(name)
      dispatcher = @dispatchers[name]
      dispatcher || raise "Dispatcher not found: #{name}"
      dispatcher
    end
  end

  abstract class AbstractActorContext
  end

  class ActorContext(T) < AbstractActorContext
    @mailbox : Mailbox(T)?
    def initialize(behavior : AbstractBehavior(T), ref : ActorRef(T), @system : AbstractActorSystem)
      @behavior = behavior
      @ref = ref
    end

    def mailbox=(mailbox : Mailbox(T))
      @mailbox = mailbox
    end

    def tell(message : T)
      raise "Mailbox not initialized" unless @mailbox
      mbox = @mailbox.as(Mailbox(T))
      mbox << message
    end

    def << (message : T)
      tell message
    end

    def start
      @mailbox = @system.mailboxes.create(@system.dispatchers.default, self)
    end

    def on_message(message : T)
      @behavior.receive(message, self)
    end
  end

  class ActorRef(T)
    getter id : Int32

    def initialize(@system : AbstractActorSystem)
      @id = @system.next_id()
    end

    def <<(message : T)
      context = @system.context @id
      raise "Context not found" if context.nil?
      context << message
    end
  end

  class ActorRegistry
    @system : AbstractActorSystem?
    def initialize()
      @actors = {} of Int32 => AbstractActorContext
      @mutex = Mutex.new
    end

    def system=(system : AbstractActorSystem?) forall T
      @system = system
    end

    def spawn(behavior : AbstractBehavior(T)) : ActorRef(T) forall T
      raise "System not initialized" unless @system
      ref = ActorRef(T).new(@system.as(ActorSystem))
      context = ActorContext(T).new(behavior, ref, @system.as(AbstractActorSystem))
      @actors[ref.id] = context
      context.start
      ref
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
    def initialize
      @dispatchers = {} of String => Dispatcher
    end

    def register(name : String, dispatcher : Dispatcher)
      @dispatchers[name] = dispatcher
    end

    def default
      # ||= is a safe way to initialize a variable only once
      # if there is no default dispatcher, create one and register it
      @dispatchers["default"] ||= ParallelDispatcher.new
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

    def self.new(main_behavior : AbstractBehavior(T)) forall T
      registry = ActorRegistry.new()
      system = ActorSystem(T).new(main_behavior, registry)
      system.initialize(main_behavior, registry)
      system
    end

    @root : ActorRef(T)?

    protected def initialize(main_behavior : AbstractBehavior(T), registry : ActorRegistry) forall T
      registry.system = self
      @registry = registry
      @main_behavior = main_behavior
      # @root = registry.spawn(main_behavior)
    end


    def <<(message)
      @root << message if @root
    end

    def spawn(behavior : AbstractBehavior) : ActorRef
      raise "System not initialized" unless @registry
      @registry.as(ActorRegistry).spawn(behavior)
    end
  end

  abstract class AbstractBehavior(T)
    def initialize()
    end

    def receive(message : T)
    end
  end

  # Utility methods for creating behaviors
  #
  # ctx.spawn setup do |message, context|
  #
  # end
  def self.setup(factory : ActorContext(T) -> AbstractBehavior(T))  forall T
    # Implement setup logic here
  end

end

record MainMessage, message : String

class Main < Movie::AbstractBehavior(MainMessage)
  @count : Int32 = 0
  def self.create()
    new()
  end

  def receive(message, context)
    puts message.message + " " + @count.to_s
    @count += 1
  end
end

class Child < Movie::AbstractBehavior(MainMessage)
  @parent : Movie::ActorRef(MainMessage)

  def self.create(parent)
    new(parent)
  end

  protected def initialize(parent)
    @parent = parent
  end

  def receive(message, context)
    # sleep(Random.new.rand(0.5..0.9))
    @parent << message
  end
end



system = Movie::ActorSystem(MainMessage).new(Main.create())
main = system.spawn(Main.create())

# 3000.times do |i|
child = system.spawn(Child.create(main))
2000000.times do |j|
  child << MainMessage.new(message: "message ")
end
# end

Process.on_terminate do
  # system.shutdown
end

sleep(1)
puts "Done"
