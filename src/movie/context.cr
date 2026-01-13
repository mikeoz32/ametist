module Movie
  abstract class AbstractActorContext
  end

  class ActorContext(T) < AbstractActorContext
    getter log : Log

    enum State
      CREATED
      STARTING
      RUNNING
      STOPPING
      STOPPED
      FAILED
      RESTARTING
      TERMINATED
    end

    @state : State = State::CREATED

    @mailbox : Mailbox(T)?
    @ref : ActorRef(T)

    @children : Array(ActorRefBase) = [] of ActorRefBase
    @watching : Array(ActorRefBase) = [] of ActorRefBase
    @watchers : Array(ActorRefBase) = [] of ActorRefBase
    @pending_children : Array(ActorRefBase) = [] of ActorRefBase
    @pending_terminations : Int32 = 0
    @pre_stop_completed : Bool = false
    @post_stop_sent : Bool = false

    def initialize(behavior : AbstractBehavior(T), @ref : ActorRef(T), @system : AbstractActorSystem)
      @behavior = behavior
      @active_behavior = behavior
      @log = Log.for(@ref.id.to_s)
    end

    def state
      @state
    end

    def ref : ActorRef(T)
      @ref
    end

    def start(internal = false)
      return if @state != State::CREATED

      dispatcher = internal ? @system.dispatchers.internal : @system.dispatchers.default

      @mailbox = @system.mailboxes.create(dispatcher, self)

      transition_to(State::STARTING)

      send_system_message(PRE_START)
    end

    def stop
      return if [@state.stopped?, @state.failed?, @state.terminated?, @state == State::STOPPING].any?

      send_system_message(STOP)
    end


    def spawn(behavior : AbstractBehavior(U)) : ActorRef(U) forall U
      raise "System not initialized" unless @system
      child = @system.spawn(behavior)

      attach_child(child)

      child.as(ActorRef(U))
    end

    def attach_child(child : ActorRef(U)) forall U
      @children << child unless @children.includes?(child)
      watch child
    end

    def watch(actor : ActorRef(U)) forall U
      return if @watching.includes?(actor)

      @watching << actor
      actor.send_system(Watch.new(@ref).as(SystemMessage))
    end

    def mailbox=(mailbox : Mailbox(T))
      @mailbox = mailbox
    end

    def tell(message : T)
      raise "Mailbox not initialized" unless @mailbox
      mbox = @mailbox.as(Mailbox(T))
      mbox << Envelope.new(message, self.@ref)
    end

    def << (message : T)
      tell message
    end

    def send_system_message(message : SystemMessage)
      raise "Mailbox not initialized" unless @mailbox
      mbox = @mailbox.as(Mailbox(T))
      mbox.send_system(Envelope.new(message, self.@ref))
    end

    def on_message(message : Envelope(T))
      log.debug { "Actor #{@ref} received message #{message.message}" }
      log.debug { "Current state: #{@state}" }
      new_behavior = @active_behavior.receive(message.message, self)
      if new_behavior.is_a?(AbstractBehavior(T))
        @active_behavior = resolve_behavior(new_behavior)
        @behavior = @active_behavior
      end
    rescue ex : Exception
      log.error(exception: ex) { "Error handling message" }
      notify_for_failure(ex)
      transition_to(State::FAILED)
    end

    def on_system_message(message : Envelope(SystemMessage))
      # TODO: handle system messages
      case message.message
      when PRE_START
        handle_pre_start
      when POST_START
        handle_post_start
      when STOP
        handle_stop
      when PRE_STOP
        handle_pre_stop
      when POST_STOP
        handle_post_stop
      when Watch
        watcher = message.message.as(Watch).actor
        unless @watchers.includes?(watcher)
          @watchers << watcher
        end
      when Unwatch
        unwatcher = message.message.as(Unwatch).actor
        unless @watchers.includes?(unwatcher)
          return
        end
        @watchers.delete(unwatcher)
      when Failed
        #Child failed
        m = message.message.as(Failed)
        # TODO: handle supervision strategy
      when Terminated
        handle_terminated(message.message.as(Terminated))
      else
        # Unknown system message - send to dead letters or log
      end
    end

    protected def resolve_behavior(behavior : AbstractBehavior(T)) : AbstractBehavior(T)
      case behavior
      when SameBehavior(T)
        @active_behavior
      when DeferredBehavior(T)
        behavior.defer(self)
      when StoppedBehavior(T)
        stop
        behavior
      else
        behavior
      end
    end

    protected def notify_for_termination
      @watchers.each do |watcher|
        watcher.send_system(Terminated.new(@ref).as(SystemMessage))
      end
    end

    protected def notify_for_failure(ex : Exception)
      @watchers.each do |watcher|
        watcher.send_system(Failed.new(@ref, ex).as(SystemMessage))
      end
    end

    protected def handle_pre_start
      @active_behavior = resolve_behavior(@behavior)
      @behavior = @active_behavior
      @active_behavior.on_signal(PRE_START)
      send_system_message(POST_START)
    rescue ex : Exception
      transition_to(State::FAILED)
      # @last_failure = ex
    end

    protected def handle_post_start
      transition_to(State::RUNNING)
      @behavior.on_signal(POST_START)
    end

    protected def handle_stop
      return if @state == State::STOPPING
      transition_to(State::STOPPING)
      @pre_stop_completed = false
      @post_stop_sent = false
      initiate_children_stop
      send_system_message(PRE_STOP)
      finalize_stop_if_ready
    end

    protected def handle_pre_stop
      @active_behavior.on_signal(PRE_STOP)
      @pre_stop_completed = true
      finalize_stop_if_ready
    end

    protected def handle_post_stop
      @active_behavior.on_signal(POST_STOP)
      transition_to(State::STOPPED)
      notify_for_termination
    end

    protected def handle_terminated(message : Terminated)
      actor = message.actor
      @watching.delete(actor)
      @children.delete(actor)

      if @pending_terminations > 0 && @pending_children.includes?(actor)
        @pending_children.delete(actor)
        @pending_terminations -= 1
        STDERR.puts "actor=#{@ref.id} pending_terminations=#{@pending_terminations} pre_stop_completed=#{@pre_stop_completed}" if ENV["DEBUG_STOP"]?
      end

      finalize_stop_if_ready
    end

    protected def initiate_children_stop
      @pending_children = @children.dup
      @pending_terminations = @pending_children.size
      STDERR.puts "actor=#{@ref.id} children=#{@pending_terminations}" if ENV["DEBUG_STOP"]?
      @pending_children.each do |child|
        child.send_system(STOP)
      end
    end

    protected def finalize_stop_if_ready
      STDERR.puts "actor=#{@ref.id} check finalize: pending=#{@pending_terminations} pre=#{@pre_stop_completed} post_sent=#{@post_stop_sent}" if ENV["DEBUG_STOP"]?
      return if @post_stop_sent
      return unless @pre_stop_completed
      return unless @pending_terminations == 0

      STDERR.puts "actor=#{@ref.id} finalize_stop" if ENV["DEBUG_STOP"]?
      @post_stop_sent = true
      send_system_message(POST_STOP)
    end

    protected def transition_to(new_state : State)
      log.debug { "Actor #{@ref} transitioning from #{@state} to #{new_state}" }
      @state = new_state
    end
  end
end
