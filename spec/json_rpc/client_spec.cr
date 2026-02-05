require "../spec_helper"
require "json"
require "../../src/json_rpc"

private class TestTransport < JsonRpc::Transport
  getter sent : Array(String)

  def initialize
    @sent = [] of String
    @on_message = nil.as(Proc(String, Nil)?)
    @on_send = nil.as(Proc(String, Nil)?)
  end

  def start(&on_message : String ->)
    @on_message = on_message
  end

  def send(message : String)
    @sent << message
    if handler = @on_send
      handler.call(message)
    end
  end

  def on_send(&block : String ->)
    @on_send = block
  end

  def emit(message : String)
    handler = @on_message
    raise "Transport not started" unless handler
    handler.call(message)
  end

  def close
  end
end

describe JsonRpc::Client do
  it "returns response result for requests" do
    transport = TestTransport.new
    client = JsonRpc::Client.new(transport)
    client.start

    transport.on_send do |message|
      json = JSON.parse(message)
      next unless json["method"]?.try(&.as_s) == "ping"
      id = json["id"]
      response = %({"jsonrpc":"2.0","id":#{id.to_json},"result":{"ok":true}})
      spawn { transport.emit(response) }
    end

    result = client.request("ping")
    result["ok"].as_bool.should be_true
  end

  it "dispatches notifications by method" do
    transport = TestTransport.new
    client = JsonRpc::Client.new(transport)
    client.start

    channel = Channel(Int32).new(1)
    client.register_notification("notice") do |params|
      channel.send(params.not_nil!["count"].as_i)
    end

    transport.emit(%({"jsonrpc":"2.0","method":"notice","params":{"count":3}}))
    channel.receive.should eq(3)
  end

  it "handles inbound requests with registered handler" do
    transport = TestTransport.new
    client = JsonRpc::Client.new(transport)
    client.start

    client.register_request("sum") do |params|
      a = params.not_nil!["a"].as_i
      b = params.not_nil!["b"].as_i
      JSON::Any.new(a + b)
    end

    transport.emit(%({"jsonrpc":"2.0","id":1,"method":"sum","params":{"a":2,"b":5}}))
    response = JSON.parse(transport.sent.last)
    response["result"].as_i.should eq(7)
  end
end
