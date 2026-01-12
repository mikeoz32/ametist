require "./spec_helper"
require "http"
require "../src/openai/client"

module OpenAI
  class FakeHttpClient
    include OpenAI::HttpClient

    struct Call
      property method : String
      property url : String
      property headers : Hash(String, String)
      property body : String | Nil

      def initialize(@method : String, @url : String, @headers : Hash(String, String), @body : String | Nil)
      end
    end

    struct Resp
      property status_code : Int32
      property body : String

      def initialize(@status_code : Int32, @body : String)
      end
    end

    property calls = [] of Call
    property response_body : String = "{}"
    property response_status : Int32 = 200

    def request(method : String, url : String, headers : Hash(String, String) = {} of String => String, body : String | IO | Nil = nil)
      calls << Call.new(method: method, url: url, headers: headers, body: body.is_a?(IO) ? body.to_s : body)
      Resp.new(response_status, response_body)
    end
  end
end

describe "OpenAI::Client" do
  it "sends models GET to /v1/models" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"object" => "list", "data" => [{"id" => "gpt-4", "object" => "model"}]}.to_json

    res = client.models

    fake.calls.size.should eq 1
    fake.calls[0].method.should eq "GET"
    fake.calls[0].url.includes?("/v1/models").should be_true
    fake.calls[0].headers["Authorization"].should eq "Bearer sk-test"
    res.data.first.id.should eq "gpt-4"
  end

  it "sends chat completions POST with typed payload" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {
      "id" => "chatcmpl-1",
      "object" => "chat.completion",
      "created" => 0,
      "model" => "gpt-4o",
      "choices" => [{"index" => 0, "message" => {"role" => "assistant", "content" => "Hello"}, "finish_reason" => "stop"}]
    }.to_json

    messages = [OpenAI::ChatCompletionRequest::ChatMessagePayload.new("developer", "Hello")]
      payload = OpenAI::ChatCompletionRequest.new(model: "gpt-4o", messages: messages)
    res = client.chat_completions(payload)

    fake.calls.size.should eq 1
    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.includes?("/v1/chat/completions").should be_true
    fake.calls[0].body.not_nil!.includes?("gpt-4o").should be_true
    res.choices.first.message.content.should eq "Hello"
  end

  it "sends legacy completions POST" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {
      "id" => "cmpl-1",
      "object" => "text.completion",
      "created" => 0,
      "model" => "gpt-3.5-turbo-instruct",
      "choices" => [{"index" => 0, "message" => {"role" => "assistant", "content" => "Hi"}}]
    }.to_json

    payload = OpenAI::CompletionRequest.new(model: "gpt-3.5-turbo-instruct", prompt: "Hi")
    client.completions(payload)

    fake.calls.size.should eq 1
    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/completions")
  end

  it "sends embeddings POST with typed payload" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {
      "object" => "list",
      "data" => [{"index" => 0, "object" => "embedding", "embedding" => [0.1, 0.2]}]
    }.to_json

    payload = OpenAI::EmbeddingsRequest.new(model: "text-embedding-3-small", input: "hello")
    res = client.embeddings(payload)

    fake.calls.size.should eq 1
    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.includes?("/v1/embeddings").should be_true
    fake.calls[0].body.not_nil!.includes?("text-embedding-3-small").should be_true
    res.data.first.embedding.size.should eq 2
  end

  it "retrieves model" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "gpt-4", "object" => "model"}.to_json

    client.retrieve_model("gpt-4")

    fake.calls[0].method.should eq "GET"
    fake.calls[0].url.should contain("/v1/models/gpt-4")
  end

  it "generates images" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"created" => 0, "data" => [] of JSON::Any}.to_json

    payload = OpenAI::ImagesGenerateRequest.new(prompt: "cat")
    client.images_generate(payload)

    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/images/generations")
  end

  it "edits images multipart" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"created" => 0, "data" => [] of JSON::Any}.to_json

    payload = OpenAI::ImageEditRequest.new(prompt: "fix")
    payload.mask_io = IO::Memory.new("MASK")
    payload.mask_filename = "mask.png"
    client.images_edit(IO::Memory.new("IMG"), "img.png", payload)

    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/images/edits")
  end

  it "creates image variations multipart" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"created" => 0, "data" => [] of JSON::Any}.to_json

    payload = OpenAI::ImageVariationRequest.new(n: 1)
    client.images_variations(IO::Memory.new("IMG"), "img.png", payload)

    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/images/variations")
  end

  it "runs moderation" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "mod", "model" => "omni", "results" => [{"flagged" => false, "categories" => nil, "category_scores" => nil}]}.to_json

    payload = OpenAI::ModerationRequest.new("hello")
    client.moderation(payload)

    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/moderations")
  end

  it "uploads file multipart" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "file", "object" => "file"}.to_json

    payload = OpenAI::UploadFileRequest.new("assistants")
    client.upload_file(IO::Memory.new("DATA"), "data.txt", payload)

    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/files")
  end

  it "lists files" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"object" => "list", "data" => [] of JSON::Any}.to_json

    client.list_files

    fake.calls[0].method.should eq "GET"
    fake.calls[0].url.should contain("/v1/files")
  end

  it "deletes file" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "file", "object" => "file"}.to_json

    client.delete_file("file")

    fake.calls[0].method.should eq "DELETE"
    fake.calls[0].url.should contain("/v1/files/file")
  end

  it "downloads file" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = "BINARY"

    client.download_file("file")

    fake.calls[0].headers["Accept"].should eq "application/octet-stream"
  end

  it "creates fine tuning job" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "ft", "model" => "ft-model"}.to_json

    payload = OpenAI::CreateFineTuningJobRequest.new("gpt-4o-mini", "file")
    client.create_fine_tuning_job(payload)

    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/fine_tuning/jobs")
  end

  it "lists fine tuning jobs" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"data" => [] of JSON::Any}.to_json

    client.list_fine_tuning_jobs

    fake.calls[0].url.should contain("/v1/fine_tuning/jobs")
  end

  it "cancels fine tuning job" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "ft", "status" => "cancelled"}.to_json

    client.cancel_fine_tuning_job("ft")

    fake.calls[0].method.should eq "POST"
    fake.calls[0].url.should contain("/v1/fine_tuning/jobs/ft/cancel")
  end

  it "lists assistants with beta header" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"object" => "list", "data" => [] of JSON::Any}.to_json

    client.list_assistants

    fake.calls[0].headers["OpenAI-Beta"].should eq "assistants=v2"
  end

  it "modifies assistant" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "asst", "object" => "assistant", "created_at" => 0, "model" => "gpt-4o"}.to_json

    payload = OpenAI::ModifyAssistantRequest.new(name: "New")
    client.modify_assistant("asst", payload)

    fake.calls[0].url.should contain("/v1/assistants/asst")
    fake.calls[0].method.should eq "POST"
  end

  it "creates thread and message" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "thread", "object" => "thread", "created_at" => 0}.to_json

    client.create_thread
    fake.calls[0].url.should contain("/v1/threads")

    fake.response_body = {"id" => "msg", "object" => "thread.message", "created_at" => 0}.to_json
    msg_payload = OpenAI::CreateMessageRequest.new("user", JSON.parse({"type" => "text", "text" => "hi"}.to_json))
    client.create_message("thread", msg_payload)

    fake.calls[1].url.should contain("/v1/threads/thread/messages")
    fake.calls[1].method.should eq "POST"
  end

  it "creates run and thread+run" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "run", "object" => "thread.run", "created_at" => 0, "thread_id" => "t"}.to_json

    run_payload = OpenAI::CreateRunRequest.new("asst")
    client.create_run("thread", run_payload)
    fake.calls[0].url.should contain("/v1/threads/thread/runs")

    tar_payload = OpenAI::CreateThreadAndRunRequest.new("asst")
    client.create_thread_and_run(tar_payload)
    fake.calls[1].url.should contain("/v1/threads/runs")
  end

  it "submits tool outputs" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "run", "object" => "thread.run", "created_at" => 0, "thread_id" => "t"}.to_json

    tool_outputs = [JSON.parse({"tool_call_id" => "1", "output" => "done"}.to_json)]
    payload = OpenAI::SubmitToolOutputsRequest.new(tool_outputs)
    client.submit_tool_outputs("t", "r", payload)

    fake.calls[0].url.should contain("/v1/threads/t/runs/r/submit_tool_outputs")
    fake.calls[0].method.should eq "POST"
  end

  it "creates vector store" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "vs", "object" => "vector_store", "created_at" => 0}.to_json

    payload = OpenAI::CreateVectorStoreRequest.new(name: "store")
    client.create_vector_store(payload)

    fake.calls[0].url.should contain("/v1/vector_stores")
  end

  it "creates batch" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "batch", "object" => "batch"}.to_json

    payload = OpenAI::CreateBatchRequest.new("file", "/v1/responses", "24h")
    client.create_batch(payload)

    fake.calls[0].url.should contain("/v1/batches")
    fake.calls[0].method.should eq "POST"
  end

  it "creates response and appends input" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"id" => "resp", "object" => "response"}.to_json

    payload = OpenAI::CreateResponseRequest.new(model: "gpt-4o", input: [] of JSON::Any)
    client.create_response(payload)
    fake.calls[0].url.should contain("/v1/responses")

    append_payload = OpenAI::AppendResponseInputRequest.new(input: [] of JSON::Any)
    client.append_response_input("resp", append_payload)
    fake.calls[1].url.should contain("/v1/responses/resp/input_items")
  end

  it "streams chat and fails fast on connection refused" do
    client = OpenAI::Client.new("sk-test", "http://127.0.0.1:9")
    messages = [OpenAI::ChatCompletionRequest::ChatMessagePayload.new("user", "hi")]
     payload = OpenAI::ChatCompletionRequest.new(model: "gpt-4o", messages: messages)

    expect_raises(IO::Error) do
      client.chat.completions_stream(payload) { |_line| }
    end
  end

  it "builds assistants list query and beta header" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"object" => "list", "data" => [] of JSON::Any}.to_json

    params = OpenAI::ListAssistantsParams.new
    params.limit = 5
    params.order = "asc"
    params.after = "cursor"
    client.list_assistants(params)

    fake.calls.size.should eq 1
    call = fake.calls[0]
    call.url.should contain("/v1/assistants")
    call.url.should contain("limit=5")
    call.url.should contain("order=asc")
    call.url.should contain("after=cursor")
    call.headers["OpenAI-Beta"].should eq "assistants=v2"
  end

  it "uses namespaced chat api" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {
      "id" => "chatcmpl-1",
      "object" => "chat.completion",
      "created" => 0,
      "model" => "gpt-4o",
      "choices" => [{"index" => 0, "message" => {"role" => "assistant", "content" => "Hi"}}]
    }.to_json

    messages = [OpenAI::ChatCompletionRequest::ChatMessagePayload.new("user", "Hi")]
    payload = OpenAI::ChatCompletionRequest.new(model: "gpt-4o", messages: messages)
    res = client.chat.completions(payload)

    fake.calls.size.should eq 1
    fake.calls[0].url.should contain("/v1/chat/completions")
    res.choices.first.message.content.should eq "Hi"
  end

  it "sends transcription multipart with typed payload" do
    fake = OpenAI::FakeHttpClient.new
    client = OpenAI::Client.new("sk-test", "https://api.openai.com", fake)
    fake.response_body = {"text" => "hello"}.to_json

    io = IO::Memory.new("AUDIO")
    payload = OpenAI::TranscriptionRequest.new("gpt-4o-audio-preview", language: "en")
    res = client.audio.transcription(io, "clip.wav", payload)

    fake.calls.size.should eq 1
    fake.calls[0].url.should contain("/v1/audio/transcriptions")
    res.text.should eq "hello"
  end
end
