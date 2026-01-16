module Movie
  module Streams
        enum StageState
          Active
          Completed
          Failed
          Cancelled
        end

        class Subscribe
          getter subscriber : ActorRefBase
          def initialize(@subscriber : ActorRefBase)
          end
        end

        class OnSubscribe
          getter subscription : Subscription
          def initialize(@subscription : Subscription)
          end
        end

        class Request
          getter n : UInt64
          def initialize(@n : UInt64)
          end
        end

        class Cancel
        end

        alias Element = Nil | Int32 | Float64 | String | Bool | Symbol

        class OnNext
          getter elem
          def initialize(@elem : Element)
          end
        end

        class OnComplete
        end

        class OnError
          getter error : Exception
          def initialize(@error : Exception)
          end
        end

        class Produce
          getter elem
          def initialize(@elem : Element)
          end
        end

        alias MessageBase = Subscribe | OnSubscribe | Request | Cancel | OnNext | OnComplete | OnError | Produce

        class Subscription
          @closed = false
          def initialize(@ref : ActorRef(MessageBase))
          end

          def request(n : UInt64)
            return if @closed || n == 0
            @ref << Request.new(n)
          end

          def cancel
            return if @closed
            @closed = true
            @ref << Cancel.new
          end
        end

        # Manual source emits via Produce messages; respects demand and terminals.
        class ManualSource < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @buffer : Array(Element) = [] of Element
          @pending_complete : Bool = false

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when Produce
              handle_produce(message)
            when OnComplete
              handle_complete
            when OnError
              fail(message.error)
            else
              # ignore
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
            drain_buffer
            STDERR.puts "source subscribed downstream" if ENV["DEBUG_STREAMS"]?
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @demand = clamp_add(@demand, msg.n)
            STDERR.puts "source request n=#{msg.n} demand=#{@demand}" if ENV["DEBUG_STREAMS"]?
            drain_buffer
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
          end

          private def handle_produce(msg : Produce)
            return if @state == StageState::Completed || @state == StageState::Failed
            unless @downstream
              STDERR.puts "source buffer elem=#{msg.elem}" if ENV["DEBUG_STREAMS"]?
              @buffer << msg.elem
              return
            end

            if @demand == 0
              STDERR.puts "source buffer elem=#{msg.elem} demand=0" if ENV["DEBUG_STREAMS"]?
              @buffer << msg.elem
              return
            end

            STDERR.puts "source emit elem=#{msg.elem}" if ENV["DEBUG_STREAMS"]?
            @downstream.not_nil! << OnNext.new(msg.elem)
            @demand -= 1
            try_emit_complete
          end

          private def handle_complete
            return if @state == StageState::Completed || @state == StageState::Failed
            @pending_complete = true
            try_emit_complete
          end

          private def fail(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @state = StageState::Failed
          end

          private def drain_buffer
            return unless @downstream
            while @demand > 0 && (elem = @buffer.shift?)
              STDERR.puts "source drain elem=#{elem} demand=#{@demand}" if ENV["DEBUG_STREAMS"]?
              @downstream.not_nil! << OnNext.new(elem)
              @demand -= 1
              try_emit_complete
            end
          end

          private def terminal?
            @state != StageState::Active
          end

          private def try_emit_complete
            return unless @pending_complete
            return unless @downstream
            return unless @buffer.empty?
            STDERR.puts "source emit complete" if ENV["DEBUG_STREAMS"]?
            @downstream.not_nil! << OnComplete.new
            @pending_complete = false
            @state = StageState::Completed
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
      end

        # Pass-through flow with demand tracking.
        class PassThroughFlow < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @upstream : Subscription?
          @downstream_demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @pending_cancel : Bool = false

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when OnSubscribe
              @upstream = message.subscription
              STDERR.puts "flow on_subscribe upstream set" if ENV["DEBUG_STREAMS"]?
              propagate_pending
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              forward_complete
            when OnError
              forward_error(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
            STDERR.puts "flow subscribed downstream" if ENV["DEBUG_STREAMS"]?
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @downstream_demand = clamp_add(@downstream_demand, msg.n)
            STDERR.puts "flow request n=#{msg.n} demand=#{@downstream_demand} upstream?=#{!!@upstream}" if ENV["DEBUG_STREAMS"]?
            @upstream.try &.request(msg.n)
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @pending_cancel = true unless @upstream
            @upstream.try &.cancel
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            return unless @downstream
            return if @downstream_demand == 0
            STDERR.puts "flow forward elem=#{msg.elem} demand_before=#{@downstream_demand}" if ENV["DEBUG_STREAMS"]?
            @downstream.not_nil! << OnNext.new(msg.elem)
            @downstream_demand -= 1
          end

          private def forward_complete
            return if terminal?
            if ds = @downstream
              ds << OnComplete.new
            end
            @state = StageState::Completed
          end

          private def forward_error(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @upstream.try &.cancel
            @state = StageState::Failed
          end

          private def terminal?
            @state != StageState::Active
          end

          private def propagate_pending
            if @state == StageState::Cancelled || @pending_cancel
              @upstream.try &.cancel
              @pending_cancel = false
              return
            end

            if @downstream_demand > 0
              STDERR.puts "flow propagate pending demand=#{@downstream_demand}" if ENV["DEBUG_STREAMS"]?
              @upstream.try &.request(@downstream_demand)
            end
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Map flow transforms elements while respecting demand.
        class MapFlow < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @upstream : Subscription?
          @downstream_demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @pending_cancel : Bool = false
          @fn : Element -> Element

          def initialize(&block : Element -> Element)
            @fn = block
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when OnSubscribe
              @upstream = message.subscription
              propagate_pending
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              forward_complete
            when OnError
              forward_error(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @downstream_demand = clamp_add(@downstream_demand, msg.n)
            @upstream.try &.request(msg.n)
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @pending_cancel = true unless @upstream
            @upstream.try &.cancel
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            return unless @downstream
            return if @downstream_demand == 0
            transformed = @fn.call(msg.elem)
            @downstream.not_nil! << OnNext.new(transformed)
            @downstream_demand -= 1
          end

          private def forward_complete
            return if terminal?
            if ds = @downstream
              ds << OnComplete.new
            end
            @state = StageState::Completed
          end

          private def forward_error(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @upstream.try &.cancel
            @state = StageState::Failed
          end

          private def terminal?
            @state != StageState::Active
          end

          private def propagate_pending
            if @state == StageState::Cancelled || @pending_cancel
              @upstream.try &.cancel
              @pending_cancel = false
              return
            end

            if @downstream_demand > 0
              @upstream.try &.request(@downstream_demand)
            end
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Tap flow executes a side-effect and passes elements through unchanged.
        class TapFlow < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @upstream : Subscription?
          @downstream_demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @pending_cancel : Bool = false
          @fn : Element ->

          def initialize(&block : Element ->)
            @fn = block
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when OnSubscribe
              @upstream = message.subscription
              propagate_pending
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              forward_complete
            when OnError
              forward_error(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @downstream_demand = clamp_add(@downstream_demand, msg.n)
            @upstream.try &.request(msg.n)
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @pending_cancel = true unless @upstream
            @upstream.try &.cancel
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            return unless @downstream
            return if @downstream_demand == 0
            spawn { @fn.call(msg.elem) }
            @downstream.not_nil! << OnNext.new(msg.elem)
            @downstream_demand -= 1
          end

          private def forward_complete
            return if terminal?
            if ds = @downstream
              ds << OnComplete.new
            end
            @state = StageState::Completed
          end

          private def forward_error(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @upstream.try &.cancel
            @state = StageState::Failed
          end

          private def terminal?
            @state != StageState::Active
          end

          private def propagate_pending
            if @state == StageState::Cancelled || @pending_cancel
              @upstream.try &.cancel
              @pending_cancel = false
              return
            end

            if @downstream_demand > 0
              @upstream.try &.request(@downstream_demand)
            end
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Filter flow drops elements that do not satisfy predicate without consuming demand.
        class FilterFlow < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @upstream : Subscription?
          @downstream_demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @pending_cancel : Bool = false
          @pred : Element -> Bool

          def initialize(&block : Element -> Bool)
            @pred = block
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when OnSubscribe
              @upstream = message.subscription
              propagate_pending
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              forward_complete
            when OnError
              forward_error(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @downstream_demand = clamp_add(@downstream_demand, msg.n)
            @upstream.try &.request(msg.n)
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @pending_cancel = true unless @upstream
            @upstream.try &.cancel
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            return unless @downstream
            unless @pred.call(msg.elem)
              if @downstream_demand > 0
                @upstream.try &.request(1_u64)
              end
              return
            end
            return if @downstream_demand == 0
            @downstream.not_nil! << OnNext.new(msg.elem)
            @downstream_demand -= 1
          end

          private def forward_complete
            return if terminal?
            if ds = @downstream
              ds << OnComplete.new
            end
            @state = StageState::Completed
          end

          private def forward_error(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @upstream.try &.cancel
            @state = StageState::Failed
          end

          private def terminal?
            @state != StageState::Active
          end

          private def propagate_pending
            if @state == StageState::Cancelled || @pending_cancel
              @upstream.try &.cancel
              @pending_cancel = false
              return
            end

            if @downstream_demand > 0
              @upstream.try &.request(@downstream_demand)
            end
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Take flow completes after emitting N elements.
        class TakeFlow < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @upstream : Subscription?
          @downstream_demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @pending_cancel : Bool = false
          @remaining : UInt64

          def initialize(n : UInt64)
            @remaining = n
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when OnSubscribe
              @upstream = message.subscription
              propagate_pending
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              forward_complete
            when OnError
              forward_error(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @downstream_demand = clamp_add(@downstream_demand, msg.n)
            @upstream.try &.request(msg.n)
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @pending_cancel = true unless @upstream
            @upstream.try &.cancel
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            return if @remaining == 0
            return unless @downstream
            return if @downstream_demand == 0
            @downstream.not_nil! << OnNext.new(msg.elem)
            @downstream_demand -= 1
            @remaining -= 1
            if @remaining == 0
              complete_take
            end
          end

          private def complete_take
            @upstream.try &.cancel
            if ds = @downstream
              ds << OnComplete.new
            end
            @state = StageState::Completed
          end

          private def forward_complete
            return if terminal?
            if ds = @downstream
              ds << OnComplete.new
            end
            @state = StageState::Completed
          end

          private def forward_error(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @upstream.try &.cancel
            @state = StageState::Failed
          end

          private def terminal?
            @state != StageState::Active
          end

          private def propagate_pending
            if @state == StageState::Cancelled || @pending_cancel
              @upstream.try &.cancel
              @pending_cancel = false
              return
            end

            if @downstream_demand > 0
              @upstream.try &.request(@downstream_demand)
            end
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Drop flow discards the first N elements before forwarding.
        class DropFlow < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @upstream : Subscription?
          @downstream_demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @pending_cancel : Bool = false
          @pending_drop : UInt64

          def initialize(n : UInt64)
            @pending_drop = n
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when OnSubscribe
              @upstream = message.subscription
              propagate_pending
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              forward_complete
            when OnError
              forward_error(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @downstream_demand = clamp_add(@downstream_demand, msg.n)
            extra = @pending_drop > 0 ? clamp_add(msg.n, @pending_drop) : msg.n
            @upstream.try &.request(extra)
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @pending_cancel = true unless @upstream
            @upstream.try &.cancel
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            if @pending_drop > 0
              @pending_drop -= 1
              @upstream.try &.request(1_u64) if @downstream_demand > 0
              return
            end
            return unless @downstream
            return if @downstream_demand == 0
            @downstream.not_nil! << OnNext.new(msg.elem)
            @downstream_demand -= 1
          end

          private def forward_complete
            return if terminal?
            if ds = @downstream
              ds << OnComplete.new
            end
            @state = StageState::Completed
          end

          private def forward_error(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @upstream.try &.cancel
            @state = StageState::Failed
          end

          private def terminal?
            @state != StageState::Active
          end

          private def propagate_pending
            if @state == StageState::Cancelled || @pending_cancel
              @upstream.try &.cancel
              @pending_cancel = false
              return
            end

            if @downstream_demand > 0
              extra = @pending_drop > 0 ? clamp_add(@downstream_demand, @pending_drop) : @downstream_demand
              @upstream.try &.request(extra)
            end
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Sink that collects elements; driven by Request/Cancel messages.
        class CollectSink < AbstractBehavior(MessageBase)
          getter state : StageState = StageState::Active
          @upstream : Subscription?
          @out : Channel(Element)
          @signals : Channel(Symbol)?
          @pending_demand : UInt64 = 0u64

          def initialize(@out : Channel(Element), @signals : Channel(Symbol)? = nil)
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when OnSubscribe
              @upstream = message.subscription
              flush_pending_demand
              cancel_if_needed
              STDERR.puts "sink on_subscribe pending=#{@pending_demand} state=#{@state}" if ENV["DEBUG_STREAMS"]?
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              @state = StageState::Completed
              notify(:complete)
            when OnError
              @state = StageState::Failed
              @upstream.try &.cancel
              notify(:error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            STDERR.puts "sink recv elem=#{msg.elem}" if ENV["DEBUG_STREAMS"]?
            @out.send(msg.elem)
          end

          private def handle_request(msg : Request)
            return if terminal?
            if up = @upstream
              STDERR.puts "sink request upstream n=#{msg.n}" if ENV["DEBUG_STREAMS"]?
              up.request(msg.n)
            else
              STDERR.puts "sink pending request n=#{msg.n}" if ENV["DEBUG_STREAMS"]?
              @pending_demand = clamp_add(@pending_demand, msg.n)
            end
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            if up = @upstream
              up.cancel
            end
            notify(:cancel)
          end

          private def flush_pending_demand
            return unless @pending_demand > 0
            if up = @upstream
              STDERR.puts "sink flush pending demand=#{@pending_demand}" if ENV["DEBUG_STREAMS"]?
              up.request(@pending_demand)
              @pending_demand = 0u64
            end
          end

          private def cancel_if_needed
            return unless @state == StageState::Cancelled
            @upstream.try &.cancel
          end

          private def notify(sym : Symbol)
            @signals.try { |ch| spawn { ch.send(sym) } }
          end

          private def terminal?
            @state != StageState::Active
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Wraps pipeline materialization results.
        struct MaterializedPipeline(T)
          getter system : ActorSystem(MessageBase)
          getter source : ActorRef(MessageBase)
          getter sink : ActorRef(MessageBase)
          getter completion : Future(T)
          getter cancel : ->
          getter out_channel : Channel(Element)?

          def initialize(@system : ActorSystem(MessageBase), @source : ActorRef(MessageBase), @sink : ActorRef(MessageBase), @completion : Future(T), @cancel : ->, @out_channel : Channel(Element)? = nil)
          end
        end

        # Internal flow that surfaces completion/error/cancel to a Promise.
        class CompletionFlow < AbstractBehavior(MessageBase)
          @downstream : ActorRef(MessageBase)?
          @upstream : Subscription?
          @downstream_demand : UInt64 = 0u64
          @state : StageState = StageState::Active
          @pending_cancel : Bool = false
          @promise : Promise(Nil)

          def initialize(@promise : Promise(Nil))
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when Subscribe
              handle_subscribe(message, context)
            when OnSubscribe
              @upstream = message.subscription
              propagate_pending
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              forward_complete
            when OnError
              forward_error(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_subscribe(msg : Subscribe, context)
            return if @state != StageState::Active
            return if @downstream
            @downstream = msg.subscriber.as(ActorRef(MessageBase))
            sub = Subscription.new(context.ref)
            @downstream.not_nil! << OnSubscribe.new(sub)
          end

          private def handle_request(msg : Request)
            return unless @state == StageState::Active
            @downstream_demand = clamp_add(@downstream_demand, msg.n)
            @upstream.try &.request(msg.n)
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @pending_cancel = true unless @upstream
            @upstream.try &.cancel
            @promise.try_cancel
          end

          private def handle_on_next(msg : OnNext)
            return if @state == StageState::Completed || @state == StageState::Failed
            return unless @downstream
            return if @downstream_demand == 0
            @downstream.not_nil! << OnNext.new(msg.elem)
            @downstream_demand -= 1
          end

          private def forward_complete
            return if terminal?
            if ds = @downstream
              ds << OnComplete.new
            end
            @promise.try_success(nil)
            @state = StageState::Completed
          end

          private def forward_error(error : Exception)
            return if terminal?
            if ds = @downstream
              ds << OnError.new(error)
            end
            @upstream.try &.cancel
            @promise.try_failure(error)
            @state = StageState::Failed
          end

          private def terminal?
            @state != StageState::Active
          end

          private def propagate_pending
            if @state == StageState::Cancelled || @pending_cancel
              @upstream.try &.cancel
              @pending_cancel = false
              return
            end

            if @downstream_demand > 0
              @upstream.try &.request(@downstream_demand)
            end
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end

        # Build and materialize a simple source -> flows -> sink pipeline with auto-subscriptions.
        def self.build_pipeline(source : AbstractBehavior(MessageBase), flows : Array(AbstractBehavior(MessageBase)), sink : AbstractBehavior(MessageBase), initial_demand : UInt64 = 0u64)
          promise = Promise(Nil).new
          ref_ch = Channel(Tuple(ActorRef(MessageBase), ActorRef(MessageBase))).new(1)

          main = Behaviors(MessageBase).setup do |context|
            src = context.spawn(source)
            flow_refs = flows.map { |flow| context.spawn(flow) }
            completion = context.spawn(CompletionFlow.new(promise))
            sink_actor = context.spawn(sink)

            chain = flow_refs + [completion]
            downstream = sink_actor
            chain.reverse_each do |up_actor|
              up_actor << Subscribe.new(downstream)
              downstream = up_actor
            end

            src << Subscribe.new(downstream)

            if initial_demand > 0
              sink_actor << Request.new(initial_demand)
            end

            ref_ch.send({src, sink_actor})
            Behaviors(MessageBase).same
          end

          system = ActorSystem(MessageBase).new(main)
          refs = ref_ch.receive
          source_ref, sink_ref = refs
          cancel_proc = ->{ sink_ref << Cancel.new }
          MaterializedPipeline(Nil).new(system, source_ref, sink_ref, promise.future, cancel_proc)
        end

        # Build pipeline that collects into a channel for external consumers.
        def self.build_collecting_pipeline(source : AbstractBehavior(MessageBase), flows : Array(AbstractBehavior(MessageBase)) = [] of AbstractBehavior(MessageBase), initial_demand : UInt64 = 0u64, channel_capacity : Int32 = 0)
          out_ch = Channel(Element).new(channel_capacity)
          pipeline = build_pipeline(source, flows, CollectSink.new(out_ch), initial_demand)
          MaterializedPipeline(Nil).new(pipeline.system, pipeline.source, pipeline.sink, pipeline.completion, pipeline.cancel, out_ch)
        end

        # Build pipeline that folds elements to a single value and completes a Future with the accumulator.
        def self.build_fold_pipeline(source : AbstractBehavior(MessageBase), flows : Array(AbstractBehavior(MessageBase)), initial : T, reducer : T, Element -> T, initial_demand : UInt64 = 0u64) forall T
          promise = Promise(T).new
          fold_sink = FoldSink(T).new(initial, reducer, promise)
          ref_ch = Channel(Tuple(ActorRef(MessageBase), ActorRef(MessageBase))).new(1)

          main = Behaviors(MessageBase).setup do |context|
            src = context.spawn(source)
            flow_refs = flows.map { |flow| context.spawn(flow) }
            sink_actor = context.spawn(fold_sink)

            downstream = sink_actor
            flow_refs.reverse_each do |up_actor|
              up_actor << Subscribe.new(downstream)
              downstream = up_actor
            end

            src << Subscribe.new(downstream)

            sink_actor << Request.new(initial_demand > 0 ? initial_demand : UInt64::MAX)

            ref_ch.send({src, sink_actor})
            Behaviors(MessageBase).same
          end

          system = ActorSystem(MessageBase).new(main)
          source_ref, sink_ref = ref_ch.receive
          cancel_proc = ->{ sink_ref << Cancel.new }
          MaterializedPipeline(T).new(system, source_ref, sink_ref, promise.future, cancel_proc)
        end

        # Fold sink reduces elements with an accumulator and completes a promise.
        class FoldSink(T) < AbstractBehavior(MessageBase)
          @upstream : Subscription?
          @state : StageState = StageState::Active
          @acc : T
          @reducer : T, Element -> T
          @promise : Promise(T)
          @pending_demand : UInt64 = 0u64

          def initialize(@acc : T, @reducer : T, Element -> T, @promise : Promise(T))
          end

          def receive(message : MessageBase, context : ActorContext(MessageBase))
            case message
            when OnSubscribe
              @upstream = message.subscription
              flush_pending_demand
            when Request
              handle_request(message)
            when Cancel
              handle_cancel
            when OnNext
              handle_on_next(message)
            when OnComplete
              complete_success
            when OnError
              fail(message.error)
            end
            Behaviors(MessageBase).same
          end

          private def handle_on_next(msg : OnNext)
            return if terminal?
            @acc = @reducer.call(@acc, msg.elem)
          end

          private def handle_request(msg : Request)
            return if terminal?
            if up = @upstream
              up.request(msg.n)
            else
              @pending_demand = clamp_add(@pending_demand, msg.n)
            end
          end

          private def handle_cancel
            return if terminal?
            @state = StageState::Cancelled
            @upstream.try &.cancel
            @promise.try_cancel
          end

          private def complete_success
            return if terminal?
            @promise.try_success(@acc)
            @state = StageState::Completed
          end

          private def fail(error : Exception)
            return if terminal?
            @upstream.try &.cancel
            @promise.try_failure(error)
            @state = StageState::Failed
          end

          private def flush_pending_demand
            return unless @pending_demand > 0
            @upstream.try &.request(@pending_demand)
            @pending_demand = 0u64
          end

          private def terminal?
            @state != StageState::Active
          end

          private def clamp_add(current : UInt64, delta : UInt64) : UInt64
            max = UInt64::MAX
            if delta > max - current
              max
            else
              current + delta
            end
          end
        end
      end
    end
