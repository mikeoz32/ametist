module Movie
  class Envelope(T)
    def initialize(@message : T, @sender : ActorRefBase)
    end

    def message
      @message
    end

    def sender
      @sender
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

    def send(message)
        @inbox.enqueue(message)
        # @dispatcher.dispatch(self) unless @scheduled
        # @scheduled = true
        schedule_dispatch
    end

    def send_system(message)
        @system.enqueue(message)
        # @dispatcher.dispatch(self) unless @scheduled
        # @scheduled = true
        schedule_dispatch
    end

    def <<(message)
      send(message)
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
