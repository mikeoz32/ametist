require "../spec_helper"
require "json"
require "../../src/agency/runtime/extension"
require "../../src/agency/mcp/adapter"
require "../../src/agency/mcp/client"
require "../../src/json_rpc"

private class ToolCaptureLLMClient < Agency::LLMClient
  def initialize(@channel : Channel(Array(String)), @response : String)
    super("dummy-key")
  end

  def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
    @channel.send(tools.map(&.name))
    @response
  end
end

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

describe Agency::AgencyExtension do
  it "registers MCP tools for a specific agent" do
    system = Agency.spec_system
    channel = Channel(Array(String)).new(2)
    client = ToolCaptureLLMClient.new(channel, {"type" => "final", "content" => "ok"}.to_json)
    extension = Agency::AgencyExtension.new(system, client, "gpt-3.5-turbo")

    transport = TestTransport.new
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

      list_req = JSON.parse(transport.outgoing.receive)
      list_id = list_req["id"]
      transport.emit(JSON.parse(%({
        "jsonrpc":"2.0",
        "id":#{list_id},
        "result":{
          "tools":[{"name":"echo","description":"Echo","inputSchema":{"type":"object"}}]
        }
      })) )
    end

    specs = extension.register_mcp_server("agent-1", "noop", transport: transport).await(2.seconds)
    specs.first.name.should eq("echo")

    extension.run("hello", "s1", "gpt-3.5-turbo", "agent-1").await(6.seconds)
    tools = channel.receive
    tools.includes?("noop.echo").should be_true
  end
end
