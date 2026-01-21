module Movie
  class Envelope(T)
    getter message : T
    getter sender : ActorRefBase?

    def initialize(@message : T, @sender : ActorRefBase?)
    end
  end

  class Mailbox(T)
    @scheduled = false
    @processing = false

    def initialize(@dispatcher : Dispatcher, @context : ActorContext(T))
      @inbox = Queue(Envelope(T)).new
      @system = Queue(Envelope(SystemMessage)).new
      @mutex = Mutex.new
    end

    def dispatch
      @processing = true
      @system.dequeue do |message|
        @context.on_system_message(message) unless message.nil?
      end
      @inbox.dequeue do |message|
        @context.on_message(message) unless message.nil?
      end

      @processing = false
      @scheduled = false

      if @inbox.size > 0 || @system.size > 0
        schedule_dispatch
        puts "Resheculing"
      end
    end

    def send(message : Envelope(T))
      @inbox.enqueue(message)
      schedule_dispatch
    end

    def send_system(message : Envelope(SystemMessage))
      @system.enqueue(message)
      schedule_dispatch
    end

    def <<(message : Envelope(T))
      send(message)
    end

    def purge_inbox
      @inbox = Queue(Envelope(T)).new
    end

    private def schedule_dispatch
      return if @scheduled || @processing
      @dispatcher.dispatch(self)
      @scheduled = true
    end
  end

  class MailboxManager
    def create(dispatcher, context)
      Mailbox.new(dispatcher, context)
    end
  end
end
