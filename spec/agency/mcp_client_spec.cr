require "../spec_helper"
require "json"
require "../../src/agency/mcp/client"
require "../../src/json_rpc"

private class TestTransport < JsonRpc::Transport
  getter outgoing : Channel(String)

  def initialize
    @outgoing = Channel(String).new(16)
    @incoming = Channel(String).new(16)
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

describe Agency::MCP::Client do
  it "initializes and lists tools" do
    transport = TestTransport.new
    client = Agency::MCP::Client.new(transport, "agency", "0.1.0")
    client.start

    spawn do
      init_req = JSON.parse(transport.outgoing.receive)
      init_req["method"].as_s.should eq("initialize")
      init_id = init_req["id"]
      transport.emit(JSON.parse(%({
        "jsonrpc":"2.0",
        "id":#{init_id},
        "result":{
          "protocolVersion":"2025-11-25",
          "capabilities":{ "tools":{}, "resources":{}, "prompts":{}, "logging":{} },
          "serverInfo":{ "name":"mock", "version":"1.0" }
        }
      })) )

      initialized = JSON.parse(transport.outgoing.receive)
      initialized["method"].as_s.should eq("notifications/initialized")

      list_req = JSON.parse(transport.outgoing.receive)
      list_req["method"].as_s.should eq("tools/list")
      list_id = list_req["id"]
      transport.emit(JSON.parse(%({
        "jsonrpc":"2.0",
        "id":#{list_id},
        "result":{
          "tools":[{"name":"echo","description":"Echo","inputSchema":{"type":"object"}}]
        }
      })) )
    end

    client.initialize_connection
    client.server_info.not_nil!.name.should eq("mock")
    client.server_capabilities.not_nil!.tools.should_not be_nil
    list = client.list_tools
    list.tools.size.should eq(1)
    list.tools.first.name.should eq("echo")
  end

  it "requests completion suggestions" do
    transport = TestTransport.new
    client = Agency::MCP::Client.new(transport, "agency", "0.1.0")
    client.start

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

      complete_req = JSON.parse(transport.outgoing.receive)
      complete_req["method"].as_s.should eq("completion/complete")
      complete_id = complete_req["id"]
      transport.emit(JSON.parse(%({
        "jsonrpc":"2.0",
        "id":#{complete_id},
        "result":{
          "completion":{
            "values":["python","pytorch"],
            "total":2,
            "hasMore":false
          }
        }
      })) )
    end

    client.initialize_connection
    params = Agency::MCP::CompletionParams.new(
      Agency::MCP::CompletionReference.new("ref/prompt", "code_review"),
      Agency::MCP::CompletionArgument.new("language", "py")
    )
    result = client.complete(params)
    result.completion.values.first.should eq("python")
  end
end
