require "../spec_helper"
require "../../src/agency/stores/embedder_extension"

private class FakeResponse
  getter status_code : Int32
  getter body : String

  def initialize(@status_code : Int32, @body : String)
  end
end

private class FakeHttpClient
  include OpenAI::HttpClient

  def request(method : String, url : String, headers : Hash(String, String) = {} of String => String, body : String | IO | Nil = nil)
    response_body = {
      "object" => "list",
      "model" => "test",
      "data" => [
        {"index" => 1, "object" => "embedding", "embedding" => [0.3, 0.4]},
        {"index" => 0, "object" => "embedding", "embedding" => [0.1, 0.2]},
      ],
    }.to_json
    FakeResponse.new(200, response_body)
  end
end

private class ErrorHttpClient
  include OpenAI::HttpClient

  def request(method : String, url : String, headers : Hash(String, String) = {} of String => String, body : String | IO | Nil = nil)
    FakeResponse.new(500, {"error" => "boom"}.to_json)
  end
end

private class SlowHttpClient
  include OpenAI::HttpClient

  def request(method : String, url : String, headers : Hash(String, String) = {} of String => String, body : String | IO | Nil = nil)
    sleep 50.milliseconds
    FakeResponse.new(200, {"object" => "list", "data" => [] of Int32}.to_json)
  end
end

describe Agency::EmbedderExtension do
  it "returns embeddings in index order as Float32 vectors" do
    system = Agency.spec_system
    client = OpenAI::Client.new("dummy-key", "http://example.test", FakeHttpClient.new)
    embedder = Agency::EmbedderExtension.new(system, client, "test-model")

    embeddings = embedder.embed(["one", "two"]).await(1.second)
    embeddings.size.should eq(2)
    embeddings[0].should eq([0.1_f32, 0.2_f32])
    embeddings[1].should eq([0.3_f32, 0.4_f32])
  end

  it "wraps API errors as EmbedderError" do
    system = Agency.spec_system
    client = OpenAI::Client.new("dummy-key", "http://example.test", ErrorHttpClient.new)
    embedder = Agency::EmbedderExtension.new(system, client, "test-model")

    expect_raises(Agency::EmbedderError) do
      embedder.embed(["bad"]).await(1.second)
    end
  end

  it "wraps timeouts as EmbedderError" do
    system = Agency.spec_system
    client = OpenAI::Client.new("dummy-key", "http://example.test", SlowHttpClient.new)
    embedder = Agency::EmbedderExtension.new(system, client, "test-model")

    expect_raises(Agency::EmbedderError) do
      embedder.embed(["slow"], timeout: 1.millisecond).await(1.second)
    end
  end
end
