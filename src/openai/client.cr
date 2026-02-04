require "json"
require "uri"
require "http/client"
require "time"
require "random/secure"
require "./types"

module OpenAI
  # Small protocol for HTTP adapters we can swap in tests.
  module HttpClient
    abstract def request(method : String, url : String, headers : Hash(String, String) = {} of String => String, body : String | IO | Nil = nil)
  end

  # Simple HTTP client wrapper so tests can inject a fake client.
  class DefaultHttpClient
    include HttpClient

    def request(method : String, url : String, headers : Hash(String, String) = {} of String => String, body : String | IO | Nil = nil)
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      path = uri.path
      path += "?#{uri.query}" if uri.query

      request_headers = HTTP::Headers.new
      headers.each { |k, v| request_headers[k] = v }
      req = HTTP::Request.new(method, path, request_headers)

      if body
        req.headers["Content-Type"] = headers["Content-Type"]? || "application/json"
        req.body = body
      end

      begin
        client.exec(req)
      ensure
        client.close
      end
    end
  end

  class Error < Exception; end
  class ApiError < Error
    property status : Int32
    property body : String

    def initialize(@status : Int32, @body : String)
      super("OpenAI API Error: #{@status}")
    end
  end

  class Client
    @http_client : HttpClient
    @chat : ChatApi?
    @embeddings : EmbeddingsApi?
    @images : ImagesApi?
    @moderation : ModerationApi?
    @audio : AudioApi?
    @files : FilesApi?
    @fine_tuning : FineTuningApi?
    @assistants : AssistantsApi?
    @threads : ThreadsApi?
    @vector_stores : VectorStoresApi?
    @batches : BatchesApi?
    @responses : ResponsesApi?
    @models : ModelsApi?

    def initialize(@api_key : String, @base_url : String = "https://api.openai.com", http_client : HttpClient? = nil)
      @http_client = (http_client || DefaultHttpClient.new)
    end

    def chat : ChatApi
      @chat ||= ChatApi.new(self)
    end

    def embeddings : EmbeddingsApi
      @embeddings ||= EmbeddingsApi.new(self)
    end

    def images : ImagesApi
      @images ||= ImagesApi.new(self)
    end

    def moderation : ModerationApi
      @moderation ||= ModerationApi.new(self)
    end

    def audio : AudioApi
      @audio ||= AudioApi.new(self)
    end

    def files : FilesApi
      @files ||= FilesApi.new(self)
    end

    def fine_tuning : FineTuningApi
      @fine_tuning ||= FineTuningApi.new(self)
    end

    def assistants : AssistantsApi
      @assistants ||= AssistantsApi.new(self)
    end

    def threads : ThreadsApi
      @threads ||= ThreadsApi.new(self)
    end

    def vector_stores : VectorStoresApi
      @vector_stores ||= VectorStoresApi.new(self)
    end

    def batches : BatchesApi
      @batches ||= BatchesApi.new(self)
    end

    def responses : ResponsesApi
      @responses ||= ResponsesApi.new(self)
    end

    def models : ModelsApi
      @models ||= ModelsApi.new(self)
    end

    # List assistants
    # Returns a list of assistants (requires OpenAI-Beta: assistants=v2 header).
    def list_assistants(params : ListAssistantsParams = ListAssistantsParams.new) : AssistantList
      query = [] of String
      query << "limit=#{params.limit}" if params.limit
      query << "order=#{params.order}" if params.order
      query << "after=#{params.after}" if params.after
      query << "before=#{params.before}" if params.before
      path = "/v1/assistants"
      path += "?#{query.join("&")}" unless query.empty?
      AssistantList.from_json(request(path, headers: beta_assistants_header))
    end

    # Create assistant
    # Create an assistant with a model and optional instructions, tools, and resources (assistants=v2 beta header required).
    def create_assistant(payload : CreateAssistantRequest) : Assistant
      Assistant.from_json(request("/v1/assistants", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # Retrieve assistant
    # Retrieves an assistant (assistants=v2 beta header required).
    def retrieve_assistant(assistant_id : String) : Assistant
      Assistant.from_json(request("/v1/assistants/#{assistant_id}", headers: beta_assistants_header))
    end

    # Modify assistant
    # Modifies an assistant (assistants=v2 beta header required).
    def modify_assistant(assistant_id : String, payload : ModifyAssistantRequest) : Assistant
      Assistant.from_json(request("/v1/assistants/#{assistant_id}", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # Delete assistant
    # Delete an assistant (assistants=v2 beta header required).
    def delete_assistant(assistant_id : String) : DeletionStatus
      DeletionStatus.from_json(request("/v1/assistants/#{assistant_id}", method: "DELETE", headers: beta_assistants_header))
    end

    # Create thread
    # Create a thread (assistants=v2 beta header required).
    def create_thread(payload : CreateThreadRequest = CreateThreadRequest.new) : Thread
      Thread.from_json(request("/v1/threads", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # Retrieve thread
    # Retrieves a thread (assistants=v2 beta header required).
    def retrieve_thread(thread_id : String) : Thread
      Thread.from_json(request("/v1/threads/#{thread_id}", headers: beta_assistants_header))
    end

    # Create message
    # Create a message in a thread (assistants=v2 beta header required).
    def create_message(thread_id : String, payload : CreateMessageRequest) : ThreadMessage
      ThreadMessage.from_json(request("/v1/threads/#{thread_id}/messages", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # List messages
    # Returns a list of messages for a given thread (assistants=v2 beta header required).
    def list_messages(thread_id : String, params : ListMessagesParams = ListMessagesParams.new) : ThreadMessageList
      path = "/v1/threads/#{thread_id}/messages"
      query = [] of String
      query << "limit=#{params.limit}" if params.limit
      query << "order=#{params.order}" if params.order
      query << "after=#{params.after}" if params.after
      query << "before=#{params.before}" if params.before
      query << "run_id=#{params.run_id}" if params.run_id
      path += "?#{query.join("&")}" unless query.empty?
      ThreadMessageList.from_json(request(path, headers: beta_assistants_header))
    end

    # Retrieve message
    # Retrieve a single message (assistants=v2 beta header required).
    def retrieve_message(thread_id : String, message_id : String) : ThreadMessage
      ThreadMessage.from_json(request("/v1/threads/#{thread_id}/messages/#{message_id}", headers: beta_assistants_header))
    end

    # Create run
    # Create a run (assistants=v2 beta header required).
    def create_run(thread_id : String, payload : CreateRunRequest) : ThreadRun
      ThreadRun.from_json(request("/v1/threads/#{thread_id}/runs", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # Create thread and run
    # Create a thread and run it in one request (assistants=v2 beta header required).
    def create_thread_and_run(payload : CreateThreadAndRunRequest) : ThreadRun
      ThreadRun.from_json(request("/v1/threads/runs", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # List runs
    # Returns a list of runs belonging to a thread (assistants=v2 beta header required).
    def list_runs(thread_id : String) : ThreadRunList
      ThreadRunList.from_json(request("/v1/threads/#{thread_id}/runs", headers: beta_assistants_header))
    end

    # Retrieve run
    # Retrieves a run (assistants=v2 beta header required).
    def retrieve_run(thread_id : String, run_id : String) : ThreadRun
      ThreadRun.from_json(request("/v1/threads/#{thread_id}/runs/#{run_id}", headers: beta_assistants_header))
    end

    # Cancel run
    # Cancels a run (assistants=v2 beta header required).
    def cancel_run(thread_id : String, run_id : String) : ThreadRun
      ThreadRun.from_json(request("/v1/threads/#{thread_id}/runs/#{run_id}/cancel", method: "POST", body: "", headers: beta_assistants_header))
    end

    # List run steps
    # Returns a list of run steps belonging to a run (assistants=v2 beta header required).
    def list_run_steps(thread_id : String, run_id : String) : ThreadRunStepList
      ThreadRunStepList.from_json(request("/v1/threads/#{thread_id}/runs/#{run_id}/steps", headers: beta_assistants_header))
    end

    # Retrieve run step
    # Retrieves a run step (assistants=v2 beta header required).
    def retrieve_run_step(thread_id : String, run_id : String, step_id : String) : ThreadRunStep
      ThreadRunStep.from_json(request("/v1/threads/#{thread_id}/runs/#{run_id}/steps/#{step_id}", headers: beta_assistants_header))
    end

    # Submit tool outputs to a run
    # When a run has the `required_action` of type `submit_tool_outputs` this endpoint is used to submit the outputs (assistants=v2 beta header required).
    def submit_tool_outputs(thread_id : String, run_id : String, payload : SubmitToolOutputsRequest) : ThreadRun
      ThreadRun.from_json(request("/v1/threads/#{thread_id}/runs/#{run_id}/submit_tool_outputs", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # Create vector store
    # Create a vector store (assistants=v2 beta header required).
    def create_vector_store(payload : CreateVectorStoreRequest) : VectorStore
      VectorStore.from_json(request("/v1/vector_stores", method: "POST", body: payload.to_json, headers: beta_assistants_header))
    end

    # Retrieve vector store
    # Retrieves a vector store (assistants=v2 beta header required).
    def retrieve_vector_store(vector_store_id : String) : VectorStore
      VectorStore.from_json(request("/v1/vector_stores/#{vector_store_id}", headers: beta_assistants_header))
    end

    # List vector stores
    # Returns a list of vector stores (assistants=v2 beta header required).
    def list_vector_stores : VectorStoreList
      VectorStoreList.from_json(request("/v1/vector_stores", headers: beta_assistants_header))
    end

    # Create batch
    # Creates and executes a batch from an uploaded file of requests.
    def create_batch(payload : CreateBatchRequest) : Batch
      Batch.from_json(request("/v1/batches", method: "POST", body: payload.to_json))
    end

    # List batches
    # Returns a list of batches.
    def list_batches : BatchList
      BatchList.from_json(request("/v1/batches"))
    end

    # Retrieve batch
    # Retrieves a batch.
    def retrieve_batch(batch_id : String) : Batch
      Batch.from_json(request("/v1/batches/#{batch_id}"))
    end

    # Cancel batch
    # Cancels a batch.
    def cancel_batch(batch_id : String) : Batch
      Batch.from_json(request("/v1/batches/#{batch_id}/cancel", method: "POST", body: ""))
    end

    # Create response
    # Creates a response.
    def create_response(payload : CreateResponseRequest) : ResponseObject
      ResponseObject.from_json(request("/v1/responses", method: "POST", body: payload.to_json))
    end

    # Retrieve response
    # Retrieves a response.
    def retrieve_response(response_id : String) : ResponseObject
      ResponseObject.from_json(request("/v1/responses/#{response_id}"))
    end

    # Cancel response
    # Cancels a response.
    def cancel_response(response_id : String) : ResponseObject
      ResponseObject.from_json(request("/v1/responses/#{response_id}/cancel", method: "POST", body: ""))
    end

    # Submit input to a streaming response
    # Append input items to an existing streaming response.
    def append_response_input(response_id : String, payload : AppendResponseInputRequest) : ResponseObject
      ResponseObject.from_json(request("/v1/responses/#{response_id}/input_items", method: "POST", body: payload.to_json))
    end

    # Fetch all models from GET /v1/models.
    # No arguments; returns ModelsList with ids/owner/created and raises ApiError on non-2xx.
    def models : ModelsList
      ModelsList.from_json(request("/v1/models"))
    end

    # Retrieve a specific model via GET /v1/models/{id}.
    # Use to inspect ownership or creation time; raises ApiError if id is invalid or not accessible.
    def retrieve_model(id : String) : Model
      Model.from_json(request("/v1/models/#{id}"))
    end

    # Create a chat completion with POST /v1/chat/completions.
    # Payload must include "model" and an array of {"role","content"}; supports temperature, tools, and functions.
    # Returns ChatCompletionResponse; prefer chat_completions_stream for live tokens.
    def chat_completions(payload : ChatCompletionRequest) : ChatCompletionResponse
      ChatCompletionResponse.from_json(request("/v1/chat/completions", method: "POST", body: payload.to_json))
    end

    # Stream chat completions by POST /v1/chat/completions with stream=true.
    # Adds {"stream" => true} to payload and yields each raw SSE `data:` line (JSON delta) until "[DONE]".
    # Caller should JSON.parse yielded strings; no object mapping is done here.
    def chat_completions_stream(payload : ChatCompletionRequest, &)
      headers = base_headers
      headers["Content-Type"] = "application/json"

      uri = URI.parse(full_url("/v1/chat/completions"))
      client = HTTP::Client.new(uri)
      begin
        request_headers = HTTP::Headers.new
        payload.stream=true
        headers.each { |k, v| request_headers[k] = v }
        req = HTTP::Request.new("POST", uri.request_target, request_headers, body: payload.to_json)
        # payload_hash = JSON.parse(payload.to_json).as_h
        # payload_hash["stream"] = JSON::Any.new(true)
        # req.body = payload_hash.to_json
        client.exec(req) do |response|
          io = response.body_io
          puts response.status_code
          io.each_line do |line|
            next unless line.starts_with?("data:")
            data = line.lstrip("data:").strip
            break if data == "[DONE]"
            yield ChatCompletionChunk.from_json(data)
          end
        end
      ensure
        client.close
      end
      nil
    end

    # Generate embeddings with POST /v1/embeddings.
    # Provide "model" plus "input" (string or array of strings/tokens); returns EmbeddingsResponse with vectors.
    def embeddings(payload : EmbeddingsRequest) : EmbeddingsResponse
      EmbeddingsResponse.from_json(request("/v1/embeddings", method: "POST", body: payload.to_json))
    end

    # Legacy text completions via POST /v1/completions.
    # Works with instruct models (e.g., gpt-3.5-turbo-instruct); payload mirrors OpenAI docs and returns ChatCompletionResponse.
    def completions(payload : CompletionRequest) : ChatCompletionResponse
      ChatCompletionResponse.from_json(request("/v1/completions", method: "POST", body: payload.to_json))
    end

    # Create images with POST /v1/images/generations.
    # Payload should include "prompt" and optional model/size/response_format; returns ImagesResponse with URLs or base64 strings.
    def images_generate(payload : ImagesGenerateRequest) : ImagesResponse
      ImagesResponse.from_json(request("/v1/images/generations", method: "POST", body: payload.to_json))
    end

    # Edit an image (multipart POST /v1/images/edits).
    # Provide base image IO/filename plus payload fields like "prompt", optional "mask" => {io:, filename:}, size/response_format.
    def images_edit(image_io : IO, image_filename : String, payload : ImageEditRequest) : ImagesResponse
      parts = [
        MultipartPart.new(name: "image", content: image_io, filename: image_filename, content_type: "image/png"),
      ]
      if mask_io = payload.mask_io
        parts << MultipartPart.new(name: "mask", content: mask_io, filename: payload.mask_filename || "mask.png", content_type: "image/png")
      end
      payload_hash = JSON.parse(payload.to_json).as_h
      payload_hash.each do |k, v|
        parts << MultipartPart.new(name: k, content: v.to_s)
      end
      ImagesResponse.from_json(multipart_request("POST", "/v1/images/edits", parts))
    end

    # Create image variations (multipart POST /v1/images/variations).
    # Send original image IO/filename plus variation params like "n", "size", "response_format"; returns ImagesResponse.
    def images_variations(image_io : IO, image_filename : String, payload : ImageVariationRequest) : ImagesResponse
      parts = [MultipartPart.new(name: "image", content: image_io, filename: image_filename, content_type: "image/png")]
      payload_hash = JSON.parse(payload.to_json).as_h
      payload_hash.each { |k, v| parts << MultipartPart.new(name: k, content: v.to_s) }
      ImagesResponse.from_json(multipart_request("POST", "/v1/images/variations", parts))
    end

    # Run moderation via POST /v1/moderations.
    # Payload: {"model" => ..., "input" => text}; returns ModerationResponse with per-category scores and flags.
    def moderation(payload : ModerationRequest) : ModerationResponse
      ModerationResponse.from_json(request("/v1/moderations", method: "POST", body: payload.to_json))
    end

    # Speech-to-text transcription (multipart POST /v1/audio/transcriptions).
    # Attach audio file IO/filename plus "model"; payload may include language, prompt, temperature; returns TranscriptionResponse.
    def transcription(file_io : IO, filename : String, payload : TranscriptionRequest) : TranscriptionResponse
      parts = [
        MultipartPart.new(name: "file", content: file_io, filename: filename, content_type: "application/octet-stream"),
        MultipartPart.new(name: "model", content: payload.model)
      ]
      payload_hash = JSON.parse(payload.to_json).as_h
      payload_hash.delete("model")
      payload_hash.each { |k, v| parts << MultipartPart.new(name: k, content: v.to_s) }
      TranscriptionResponse.from_json(multipart_request("POST", "/v1/audio/transcriptions", parts))
    end

    # Speech translation to English (multipart POST /v1/audio/translations).
    # Same shape as transcription; outputs English text regardless of source language.
    def translation(file_io : IO, filename : String, payload : TranslationRequest) : TranscriptionResponse
      parts = [
        MultipartPart.new(name: "file", content: file_io, filename: filename, content_type: "application/octet-stream"),
        MultipartPart.new(name: "model", content: payload.model)
      ]
      payload_hash = JSON.parse(payload.to_json).as_h
      payload_hash.delete("model")
      payload_hash.each { |k, v| parts << MultipartPart.new(name: k, content: v.to_s) }
      TranscriptionResponse.from_json(multipart_request("POST", "/v1/audio/translations", parts))
    end

    # Text-to-speech with POST /v1/audio/speech.
    # Payload includes "model", "input", and optional voice/format; returns binary audio (set Accept header accordingly).
    def speech(payload : SpeechRequest)
      request("/v1/audio/speech", method: "POST", body: payload.to_json, accept: "application/octet-stream")
    end

    # Upload a file (multipart POST /v1/files).
    # Provide file IO/filename plus "purpose" (e.g., "fine-tune" or "assistants"), returns FileObject metadata.
    def upload_file(file_io : IO, filename : String, payload : UploadFileRequest) : FileObject
      parts = [
        MultipartPart.new(name: "file", content: file_io, filename: filename, content_type: "application/octet-stream"),
        MultipartPart.new(name: "purpose", content: payload.purpose)
      ]
      FileObject.from_json(multipart_request("POST", "/v1/files", parts))
    end

    # List uploaded files via GET /v1/files.
    # Returns FileList; filter by purpose client-side as needed.
    def list_files : FileList
      FileList.from_json(request("/v1/files"))
    end

    # Delete a file with DELETE /v1/files/{id}.
    # Returns the deleted FileObject; raises ApiError on missing id or permissions.
    def delete_file(file_id : String) : FileObject
      FileObject.from_json(request("/v1/files/#{file_id}", method: "DELETE"))
    end

    # Retrieve file metadata via GET /v1/files/{id}.
    # Use download_file to fetch contents; this only returns FileObject metadata.
    def retrieve_file(file_id : String) : FileObject
      FileObject.from_json(request("/v1/files/#{file_id}"))
    end

    # Download stored file bytes from GET /v1/files/{id}/content.
    # Returns binary String; caller should persist or parse based on original file type.
    def download_file(file_id : String)
      request("/v1/files/#{file_id}/content", accept: "application/octet-stream")
    end

    # Create a fine-tuning job with POST /v1/fine_tuning/jobs.
    # Payload must include "model" and "training_file" id; supports hyperparams; returns FineTuningJob status.
    def create_fine_tuning_job(payload : CreateFineTuningJobRequest) : FineTuningJob
      FineTuningJob.from_json(request("/v1/fine_tuning/jobs", method: "POST", body: payload.to_json))
    end

    # List fine-tuning jobs via GET /v1/fine_tuning/jobs.
    # Returns FineTuningJobList for pagination/monitoring progress.
    def list_fine_tuning_jobs : FineTuningJobList
      FineTuningJobList.from_json(request("/v1/fine_tuning/jobs"))
    end

    # Retrieve a fine-tuning job with GET /v1/fine_tuning/jobs/{id}.
    # Inspect state, metrics, and resulting model once completed.
    def retrieve_fine_tuning_job(id : String) : FineTuningJob
      FineTuningJob.from_json(request("/v1/fine_tuning/jobs/#{id}"))
    end

    # Cancel a fine-tuning job with POST /v1/fine_tuning/jobs/{id}/cancel.
    # Attempts to stop an active job; returns updated FineTuningJob status.
    def cancel_fine_tuning_job(id : String) : FineTuningJob
      FineTuningJob.from_json(request("/v1/fine_tuning/jobs/#{id}/cancel", method: "POST", body: ""))
    end

    private def request(path : String, *, method : String = "GET", body : String | Nil = nil, accept : String = "application/json", headers : Hash(String, String)? = nil)
      headers = base_headers.merge(headers || {} of String => String)
      headers["Content-Type"] = "application/json" if body
      headers["Accept"] = accept

      res = @http_client.request(method, full_url(path), headers, body)
      parse_response(res)
    end

    private def multipart_request(method : String, path : String, parts : Array(MultipartPart))
      boundary = "----AmetistBoundary#{Random::Secure.hex(8)}"
      body_io = IO::Memory.new
      parts.each do |part|
        body_io << "--#{boundary}\r\n"
        disp = %(Content-Disposition: form-data; name="#{part.name}")
        disp += %(; filename="#{part.filename}") if part.filename
        body_io << disp << "\r\n"
        if ct = part.content_type
          body_io << "Content-Type: #{ct}\r\n"
        end
        body_io << "\r\n"
        if io = part.content.as?(IO)
          io.rewind if io.responds_to?(:rewind)
          IO.copy(io, body_io)
        else
          body_io << part.content.to_s
        end
        body_io << "\r\n"
      end
      body_io << "--#{boundary}--\r\n"

      headers = base_headers
      headers["Content-Type"] = "multipart/form-data; boundary=#{boundary}"

      res = @http_client.request(method, full_url(path), headers, body_io)
      parse_response(res)
    end

    private def base_headers
      headers = {"Accept" => "application/json"} of String => String
      unless @api_key.empty?
        headers["Authorization"] = "Bearer #{@api_key}"
      end
      headers
    end

    private def beta_assistants_header
      {"OpenAI-Beta" => "assistants=v2"}
    end

    private def full_url(path : String)
      return path if path.starts_with?("http://") || path.starts_with?("https://")
      "#{@base_url}#{path}"
    end

    private def parse_response(res)
      status = res.status_code
      body = res.body.to_s
      if status >= 200 && status < 300
        body
      else
        raise ApiError.new(status, body)
      end
    end
  end

  struct MultipartPart
    getter name : String
    getter content : String | IO
    getter filename : String?
    getter content_type : String?

    def initialize(@name : String, @content : String | IO, @filename : String? = nil, @content_type : String? = nil)
    end
  end

  # Namespaced API helpers to provide client.chat.completions style ergonomics.
  class ChatApi
    def initialize(@client : Client); end

    def completions(payload : ChatCompletionRequest) : ChatCompletionResponse
      @client.chat_completions(payload)
    end

    # Stream chat completions; yields raw SSE lines (JSON deltas) until done.
    def completions_stream(payload : ChatCompletionRequest, &block)
      @client.chat_completions_stream(payload) do |line|
        yield line
      end
    end

    def stream(payload : ChatCompletionRequest, &block)
      @client.chat_completions_stream(payload) do |line|
        yield line
      end
    end

    def legacy_completions(payload : CompletionRequest) : ChatCompletionResponse
      @client.completions(payload)
    end
  end

  class EmbeddingsApi
    def initialize(@client : Client); end

    def create(payload : EmbeddingsRequest) : EmbeddingsResponse
      @client.embeddings(payload)
    end
  end

  class ImagesApi
    def initialize(@client : Client); end

    def generate(payload : ImagesGenerateRequest) : ImagesResponse
      @client.images_generate(payload)
    end

    def edit(image_io : IO, filename : String, payload : ImageEditRequest) : ImagesResponse
      @client.images_edit(image_io, filename, payload)
    end

    def variations(image_io : IO, filename : String, payload : ImageVariationRequest) : ImagesResponse
      @client.images_variations(image_io, filename, payload)
    end
  end

  class ModerationApi
    def initialize(@client : Client); end

    def create(payload : ModerationRequest) : ModerationResponse
      @client.moderation(payload)
    end
  end

  class AudioApi
    def initialize(@client : Client); end

    def transcription(file_io : IO, filename : String, payload : TranscriptionRequest) : TranscriptionResponse
      @client.transcription(file_io, filename, payload)
    end

    def translation(file_io : IO, filename : String, payload : TranslationRequest) : TranscriptionResponse
      @client.translation(file_io, filename, payload)
    end

    def speech(payload : SpeechRequest)
      @client.speech(payload)
    end
  end

  class FilesApi
    def initialize(@client : Client); end

    def upload(file_io : IO, filename : String, payload : UploadFileRequest) : FileObject
      @client.upload_file(file_io, filename, payload)
    end

    def list : FileList
      @client.list_files
    end

    def retrieve(file_id : String) : FileObject
      @client.retrieve_file(file_id)
    end

    def delete(file_id : String) : FileObject
      @client.delete_file(file_id)
    end

    def download(file_id : String)
      @client.download_file(file_id)
    end
  end

  class FineTuningApi
    def initialize(@client : Client); end

    def create(payload : CreateFineTuningJobRequest) : FineTuningJob
      @client.create_fine_tuning_job(payload)
    end

    def list : FineTuningJobList
      @client.list_fine_tuning_jobs
    end

    def retrieve(id : String) : FineTuningJob
      @client.retrieve_fine_tuning_job(id)
    end

    def cancel(id : String) : FineTuningJob
      @client.cancel_fine_tuning_job(id)
    end
  end

  class AssistantsApi
    def initialize(@client : Client); end

    def list(params : ListAssistantsParams = ListAssistantsParams.new) : AssistantList
      @client.list_assistants(params)
    end

    def create(payload : CreateAssistantRequest) : Assistant
      @client.create_assistant(payload)
    end

    def retrieve(id : String) : Assistant
      @client.retrieve_assistant(id)
    end

    def modify(id : String, payload : ModifyAssistantRequest) : Assistant
      @client.modify_assistant(id, payload)
    end

    def delete(id : String) : DeletionStatus
      @client.delete_assistant(id)
    end
  end

  class ThreadsApi
    def initialize(@client : Client); end

    def create(payload : CreateThreadRequest = CreateThreadRequest.new) : Thread
      @client.create_thread(payload)
    end

    def retrieve(id : String) : Thread
      @client.retrieve_thread(id)
    end

    def create_message(thread_id : String, payload : CreateMessageRequest) : ThreadMessage
      @client.create_message(thread_id, payload)
    end

    def list_messages(thread_id : String, params : ListMessagesParams = ListMessagesParams.new) : ThreadMessageList
      @client.list_messages(thread_id, params)
    end

    def retrieve_message(thread_id : String, message_id : String) : ThreadMessage
      @client.retrieve_message(thread_id, message_id)
    end

    def create_run(thread_id : String, payload : CreateRunRequest) : ThreadRun
      @client.create_run(thread_id, payload)
    end

    def create_thread_and_run(payload : CreateThreadAndRunRequest) : ThreadRun
      @client.create_thread_and_run(payload)
    end

    def list_runs(thread_id : String) : ThreadRunList
      @client.list_runs(thread_id)
    end

    def retrieve_run(thread_id : String, run_id : String) : ThreadRun
      @client.retrieve_run(thread_id, run_id)
    end

    def cancel_run(thread_id : String, run_id : String) : ThreadRun
      @client.cancel_run(thread_id, run_id)
    end

    def list_run_steps(thread_id : String, run_id : String) : ThreadRunStepList
      @client.list_run_steps(thread_id, run_id)
    end

    def retrieve_run_step(thread_id : String, run_id : String, step_id : String) : ThreadRunStep
      @client.retrieve_run_step(thread_id, run_id, step_id)
    end

    def submit_tool_outputs(thread_id : String, run_id : String, payload : SubmitToolOutputsRequest) : ThreadRun
      @client.submit_tool_outputs(thread_id, run_id, payload)
    end
  end

  class VectorStoresApi
    def initialize(@client : Client); end

    def create(payload : CreateVectorStoreRequest) : VectorStore
      @client.create_vector_store(payload)
    end

    def retrieve(id : String) : VectorStore
      @client.retrieve_vector_store(id)
    end

    def list : VectorStoreList
      @client.list_vector_stores
    end
  end

  class BatchesApi
    def initialize(@client : Client); end

    def create(payload : CreateBatchRequest) : Batch
      @client.create_batch(payload)
    end

    def list : BatchList
      @client.list_batches
    end

    def retrieve(id : String) : Batch
      @client.retrieve_batch(id)
    end

    def cancel(id : String) : Batch
      @client.cancel_batch(id)
    end
  end

  class ResponsesApi
    def initialize(@client : Client); end

    def create(payload : CreateResponseRequest) : ResponseObject
      @client.create_response(payload)
    end

    def retrieve(id : String) : ResponseObject
      @client.retrieve_response(id)
    end

    def cancel(id : String) : ResponseObject
      @client.cancel_response(id)
    end

    def append_input(id : String, payload : AppendResponseInputRequest) : ResponseObject
      @client.append_response_input(id, payload)
    end
  end

  class ModelsApi
    def initialize(@client : Client); end

    def list : ModelsList
      @client.models
    end

    def retrieve(id : String) : Model
      @client.retrieve_model(id)
    end
  end
end
