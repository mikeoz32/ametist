require "mutex"

module Movie
  class FutureCancelled < Exception
  end

  class FutureAlreadyCompleted < Exception
  end

  class FutureTimeout < Exception
  end

  enum FutureStatus
    Pending
    Success
    Failure
    Cancelled
  end

  struct FutureResult(T)
    getter status : FutureStatus
    getter value : T?
    getter error : Exception?

    def initialize(@status : FutureStatus, @value : T? = nil, @error : Exception? = nil)
    end

    def success?
      @status == FutureStatus::Success
    end

    def failure?
      @status == FutureStatus::Failure
    end

    def cancelled?
      @status == FutureStatus::Cancelled
    end

    def pending?
      @status == FutureStatus::Pending
    end
  end

  class Future(T)
    def initialize
      @mutex = Mutex.new
      @status = FutureStatus::Pending
      @value = nil.as(T?)
      @error = nil.as(Exception?)
      @callbacks = [] of Proc(FutureResult(T), Nil)
      @waiters = [] of Channel(Nil)
    end

    def status : FutureStatus
      @mutex.synchronize { @status }
    end

    def pending?
      status == FutureStatus::Pending
    end

    def success?
      status == FutureStatus::Success
    end

    def failure?
      status == FutureStatus::Failure
    end

    def cancelled?
      status == FutureStatus::Cancelled
    end

    def result : FutureResult(T)
      @mutex.synchronize { FutureResult(T).new(@status, @value, @error) }
    end

    def await(timeout : Time::Span? = nil) : T
      res = wait_result(timeout)
      case res.status
      when FutureStatus::Success
        res.value.as(T)
      when FutureStatus::Failure
        raise res.error.not_nil!
      when FutureStatus::Cancelled
        raise FutureCancelled.new
      else
        raise "Future not completed"
      end
    end

    def on_complete(&block : FutureResult(T) ->)
      snapshot = nil
      @mutex.synchronize do
        if terminal?
          snapshot = FutureResult(T).new(@status, @value, @error)
        else
          @callbacks << block
        end
      end
      block.call(snapshot) if snapshot
    end

    protected def try_complete_success(value : T) : Bool
      publish(FutureStatus::Success, value, nil)
    end

    protected def try_complete_failure(error : Exception) : Bool
      publish(FutureStatus::Failure, nil, error)
    end

    protected def try_complete_cancel : Bool
      publish(FutureStatus::Cancelled, nil, nil)
    end

    private def terminal?
      @status != FutureStatus::Pending
    end

    private def wait_result(timeout : Time::Span?) : FutureResult(T)
      wait_ch = nil
      snapshot = nil

      @mutex.synchronize do
        if terminal?
          snapshot = FutureResult(T).new(@status, @value, @error)
        else
          wait_ch = Channel(Nil).new
          @waiters << wait_ch
        end
      end

      return snapshot.not_nil! if snapshot

      timed_out = false

      if timeout
        select
        when wait_ch.not_nil!.receive
        when timeout(timeout)
          timed_out = true
        end
      else
        wait_ch.not_nil!.receive
      end

      if timed_out
        @mutex.synchronize { @waiters.delete(wait_ch.not_nil!) }
        raise FutureTimeout.new unless terminal?
      end

      @mutex.synchronize { FutureResult(T).new(@status, @value, @error) }
    end

    private def publish(status : FutureStatus, value : T?, error : Exception?) : Bool
      callbacks = [] of Proc(FutureResult(T), Nil)
      waiters = [] of Channel(Nil)
      snapshot = nil
      transitioned = false
      @mutex.synchronize do
        return false if terminal?
        @status = status
        @value = value
        @error = error
        snapshot = FutureResult(T).new(@status, @value, @error)
        callbacks = @callbacks.dup
        @callbacks.clear
        waiters = @waiters
        @waiters = [] of Channel(Nil)
        transitioned = true
      end
      callbacks.each { |cb| cb.call(snapshot.not_nil!) }
      waiters.each do |waiter|
        begin
          waiter.send(nil)
        rescue Channel::ClosedError
        end
      end
      transitioned
    end
  end

  class Promise(T)
    getter future : Future(T)

    def initialize
      @future = Future(T).new
    end

    def success(value : T) : Nil
      raise FutureAlreadyCompleted.new unless try_success(value)
    end

    def failure(error : Exception) : Nil
      raise FutureAlreadyCompleted.new unless try_failure(error)
    end

    def cancel : Nil
      raise FutureAlreadyCompleted.new unless try_cancel
    end

    def try_success(value : T) : Bool
      @future.try_complete_success(value)
    end

    def try_failure(error : Exception) : Bool
      @future.try_complete_failure(error)
    end

    def try_cancel : Bool
      @future.try_complete_cancel
    end
  end
end
