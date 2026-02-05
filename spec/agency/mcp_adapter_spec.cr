require "../spec_helper"
require "json"
require "../../src/agency/mcp/adapter"
require "../../src/agency/mcp/client"

private class TestTransport < JsonRpc::Transport
  getter outgoing : Channel(String)

  def initialize
    @outgoing = Channel(String).new(32)
    @incoming = Channel(String).new(32)
  end

  def start(&on_message : String ->)
    spawn do
      while line = @incoming.receive?
        on_message.call(line)
      end
    end
  end

  def send(message : String)
    @outgoing.send(message)
  end

  def emit(json : JSON::Any)
    @incoming.send(json.to_json)
  end

  def close
    @incoming.close
  end
end

describe Agency::MCPAdapter do
  it "executes tool calls via MCP" do
    system = Agency.spec_system
    transport = TestTransport.new
    client = Agency::MCP::Client.new(transport, "agency", "0.1.0")
    adapter = system.spawn(Agency::MCPAdapter.behavior(client))

    spawn do
      init_req = JSON.parse(transport.outgoing.receive)
      init_id = init_req["id"]
      transport.emit(JSON.parse(%({
        "jsonrpc":"2.0",
        "id":#{init_id},
        "result":{
          "protocolVersion":"2025-11-25",
          "capabilities":{},
          "serverInfo":{ "name":"mock", "version":"1.0" }
        }
      })) )

      initialized = JSON.parse(transport.outgoing.receive)
      initialized["method"].as_s.should eq("notifications/initialized")

      call_req = JSON.parse(transport.outgoing.receive)
      call_req["method"].as_s.should eq("tools/call")
      call_id = call_req["id"]
      transport.emit(JSON.parse(%({
        "jsonrpc":"2.0",
        "id":#{call_id},
        "result":{
          "content":[{"type":"text","text":"ok"}]
        }
      })) )
    end

    result_promise = Movie::Promise(Agency::ToolResult).new
    result_receiver = system.spawn(ToolResultReceiver.new(result_promise))

    adapter.tell_from(result_receiver, Agency::ToolCall.new("echo", JSON::Any.new({} of String => JSON::Any)))
    result = result_promise.future.await(1.second)
    result.content.includes?("content").should be_true
  end
end

private class ToolResultReceiver < Movie::AbstractBehavior(Agency::ToolResult)
  def initialize(@promise : Movie::Promise(Agency::ToolResult))
  end

  def receive(message, ctx)
    @promise.try_success(message)
    Movie::Behaviors(Agency::ToolResult).same
  end
end
