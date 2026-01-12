module Movie
  abstract class AbstractActorContext
  end

  class ActorContext(T) < AbstractActorContext
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

    @children : Array(ActorRefBase) = [] of ActorRefBase
    @watching : Array(ActorRefBase) = [] of ActorRefBase
    @watchers : Array(ActorRefBase) = [] of ActorRefBase

    def initialize(behavior : AbstractBehavior(T), ref : ActorRef(T), @system : AbstractActorSystem)
      @behavior = behavior
      @active_behavior = behavior
      @ref = ref
      @log = Log.for(ref.id.to_s)
    end

    def log
      @log
      @t
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
      return if [@state.stopped?, @state.failed?, @state.terminated?].any?

      send_system_message(STOP)
    end


    def spawn(behavior : AbstractBehavior(U)) : ActorRef(U) forall U
      raise "System not initialized" unless @system
      child = @system.spawn(behavior)

      attach_child(child.as(ActorRefBase))

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
      puts "Actor #{@ref} received message #{message.message}"
      puts "Current state: #{@state}"
      new_behavior = @active_behavior.receive(message.message, self)
      if new_behavior.is_a?(AbstractBehavior(T))
        @active_behavior = resolve_behavior(new_behavior)
      end
    rescue ex : Exception
      puts "Error handling message: #{ex}"
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
        puts "Actor #{@ref} is now being watched by #{watcher}"
      when Unwatch
        unwatcher = message.message.as(Unwatch).actor
        unless @watchers.includes?(unwatcher)
          return
        end
        @watchers.delete(unwatcher)
      when Failed
        #Child failed
        m = message.message.as(Failed)
        puts "Child actor #{m.actor} failed with error: #{m.cause}"
        # TODO: handle supervision strategy
      else
        # Unknown system message - send to dead letters or log
      end
    end

    protected def resolve_behavior(behavior : AbstractBehavior(T)) : AbstractBehavior(T)
      case behavior.tag
        when BehaviorTag::DEFERRED
          behavior.as(DeferredBehavior(T)).defer(self)
        when BehaviorTag::STOPPED
          stop
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
      transition_to(State::STOPPING)
      send_system_message(PRE_STOP)
    end

    protected def handle_pre_stop
      @behavior.on_signal(PRE_STOP)
      send_system_message(POST_STOP)
    end

    protected def handle_post_stop
      @behavior.on_signal(POST_STOP)
      transition_to(State::STOPPED)
    end

    protected def transition_to(new_state : State)
      puts "Actor #{@ref} transitioning from #{@state} to #{new_state}"
      @state = new_state
    end
  end
end
