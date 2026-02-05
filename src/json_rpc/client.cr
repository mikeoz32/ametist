require "json"
require "./transport"

module JsonRpc
  class Error < Exception
    getter code : Int32
    getter data : JSON::Any?

    def initialize(@code : Int32, message : String, @data : JSON::Any? = nil)
      super(message)
    end
  end

  class Client
    def initialize(@transport : Transport)
      @pending = {} of String => Channel(JSON::Any | Error)
      @pending_mutex = Mutex.new
      @next_id = Atomic(Int64).new(0_i64)
      @request_handlers = {} of String => Proc(JSON::Any?, JSON::Any)
      @notification_handlers = {} of String => Proc(JSON::Any?, Nil)
    end

    def start
      @transport.start do |line|
        handle_line(line)
      end
    end

    def request(method : String, params : JSON::Any? = nil) : JSON::Any
      id = next_id
      channel = Channel(JSON::Any | Error).new(1)
      @pending_mutex.synchronize do
        @pending[id] = channel
      end

      payload = {
        "jsonrpc" => JSON::Any.new("2.0"),
        "id" => JSON::Any.new(id),
        "method" => JSON::Any.new(method),
      } of String => JSON::Any
      if params
        payload["params"] = params
      end

      @transport.send(payload.to_json)
      response = channel.receive
      case response
      when Error
        raise response
      else
        response
      end
    end

    def notify(method : String, params : JSON::Any? = nil)
      payload = {
        "jsonrpc" => JSON::Any.new("2.0"),
        "method" => JSON::Any.new(method),
      } of String => JSON::Any
      payload["params"] = params if params
      @transport.send(payload.to_json)
    end

    def register_request(method : String, &block : JSON::Any? -> JSON::Any)
      @request_handlers[method] = block
    end

    def register_notification(method : String, &block : JSON::Any? ->)
      @notification_handlers[method] = block
    end

    def close
      @transport.close
    end

    private def next_id : String
      @next_id.add(1).to_s
    end

    private def handle_line(line : String)
      json = JSON.parse(line)
      if json.as_a?
        json.as_a.each { |entry| handle_message(entry) }
      else
        handle_message(json)
      end
    end

    private def handle_message(message : JSON::Any)
      if method = message["method"]?
        if message["id"]?
          handle_server_request(message)
        else
          handle_notification(message)
        end
        return
      end

      if id_value = message["id"]?
        id = normalize_id(id_value)
        channel = @pending_mutex.synchronize { @pending.delete(id) }
        return unless channel

        if error = message["error"]?
          code = error["code"].as_i
          message_text = error["message"]?.try(&.as_s) || "error"
          data = error["data"]?
          channel.send(Error.new(code, message_text, data))
        else
          result = message["result"]? || JSON::Any.new(nil)
          channel.send(result)
        end
      end
    end

    private def handle_notification(message : JSON::Any)
      method = message["method"].as_s
      handler = @notification_handlers[method]?
      return unless handler
      params = message["params"]?
      handler.call(params)
    end

    private def handle_server_request(message : JSON::Any)
      method = message["method"].as_s
      id = message["id"]
      params = message["params"]?

      if handler = @request_handlers[method]?
        begin
          result = handler.call(params)
          send_result(id, result)
        rescue ex
          send_error(id, -32000, ex.message || "error")
        end
      else
        send_error(id, -32601, "Method not found", JSON::Any.new({"method" => JSON::Any.new(method)}))
      end
    end

    private def send_result(id : JSON::Any, result : JSON::Any)
      payload = JSON::Any.new({
        "jsonrpc" => JSON::Any.new("2.0"),
        "id" => id,
        "result" => result,
      })
      @transport.send(payload.to_json)
    end

    private def send_error(id : JSON::Any, code : Int32, message : String, data : JSON::Any? = nil)
      error = {"code" => JSON::Any.new(code), "message" => JSON::Any.new(message)} of String => JSON::Any
      error["data"] = data if data
      payload = JSON::Any.new({
        "jsonrpc" => JSON::Any.new("2.0"),
        "id" => id,
        "error" => JSON::Any.new(error),
      })
      @transport.send(payload.to_json)
    end

    private def normalize_id(id_value : JSON::Any) : String
      if value = id_value.as_s?
        value
      else
        id_value.to_s
      end
    end
  end
end
