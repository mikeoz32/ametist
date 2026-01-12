require "json"

module OpenAI
  struct Embedding
    include JSON::Serializable

    property index : Int32
    property embedding : Array(Float64)
    @[JSON::Field(emit_null: false)]
    property object : String? = nil
  end

  struct ChatMessage
    include JSON::Serializable

    property role : String
    property content : String
    @[JSON::Field(emit_null: false)]
    property name : String? = nil
  end

  struct Usage
    include JSON::Serializable

    property prompt_tokens : Int32?
    property completion_tokens : Int32?
    property total_tokens : Int32?
  end

  struct Model
    include JSON::Serializable

    property id : String
    property object : String
    property owned_by : String? = nil
    property created : Int64? = nil
  end

  struct ModelsList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(Model)
  end

  struct ChatCompletionChoice
    include JSON::Serializable

    property index : Int32
    property message : ChatMessage
    @[JSON::Field(key: "finish_reason")]
    property finish_reason : String? = nil
  end

  struct ChatCompletionResponse
    include JSON::Serializable

    property id : String
    property object : String
    property created : Int64
    property model : String
    property choices : Array(ChatCompletionChoice)
    property usage : Usage? = nil
  end

  # Streaming chunk for /v1/chat/completions when stream=true
  struct ChatCompletionChunk
    include JSON::Serializable

    struct Choice
      include JSON::Serializable

      struct Delta
        include JSON::Serializable

        # Optional role appears only on first chunk for a choice.
        property role : String? = nil

        # Content deltas (text or other structured parts).
        property content : JSON::Any? = nil

        # Tool call deltas (function calling).
        @[JSON::Field(key: "tool_calls")]
        property tool_calls : Array(Json)? = nil
      end

      property index : Int32
      property delta : Delta
      @[JSON::Field(key: "finish_reason")]
      property finish_reason : String? = nil
    end

    property id : String
    property object : String
    property created : Int64
    property model : String
    @[JSON::Field(key: "system_fingerprint")]
    property system_fingerprint : String? = nil
    property choices : Array(Choice)
  end

  struct EmbeddingsResponse
    include JSON::Serializable

    property data : Array(Embedding)
    property model : String?
    property object : String?
  end

  struct ImageData
    include JSON::Serializable

    @[JSON::Field(key: "b64_json")]
    property b64_json : String? = nil
    property url : String? = nil
    @[JSON::Field(key: "revised_prompt")]
    property revised_prompt : String? = nil
  end

  struct ImagesResponse
    include JSON::Serializable

    property created : Int64
    property data : Array(ImageData)
  end

  struct ModerationResult
    include JSON::Serializable

    property flagged : Bool
    property categories : JSON::Any?
    @[JSON::Field(key: "category_scores")]
    property category_scores : JSON::Any?
  end

  struct ModerationResponse
    include JSON::Serializable

    property id : String
    property model : String
    property results : Array(ModerationResult)
  end

  struct TranscriptionResponse
    include JSON::Serializable

    property text : String
    property language : String? = nil
  end

  struct FileObject
    include JSON::Serializable

    property id : String
    property object : String
    property filename : String? = nil
    property purpose : String? = nil
    property bytes : Int64? = nil
    @[JSON::Field(key: "created_at")]
    property created_at : Int64? = nil
    property status : String? = nil
  end

  struct FileList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(FileObject)
  end

  struct FineTuningJob
    include JSON::Serializable

    property id : String
    property model : String? = nil
    property status : String? = nil
  end

  struct FineTuningJobList
    include JSON::Serializable

    property data : Array(FineTuningJob)
  end

  struct Assistant
    include JSON::Serializable

    property id : String
    property object : String
    @[JSON::Field(key: "created_at")]
    property created_at : Int64
    property name : String? = nil
    property description : String? = nil
    property model : String
    property instructions : String? = nil
    property tools : Array(Json)? = nil
    @[JSON::Field(key: "tool_resources")]
    property tool_resources : Json? = nil
    property metadata : Hash(String, String)? = nil
    property temperature : Float64? = nil
    @[JSON::Field(key: "top_p")]
    property top_p : Float64? = nil
    @[JSON::Field(key: "response_format")]
    property response_format : Json? = nil
  end

  struct AssistantList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(Assistant)
    @[JSON::Field(key: "first_id")]
    property first_id : String? = nil
    @[JSON::Field(key: "last_id")]
    property last_id : String? = nil
    @[JSON::Field(key: "has_more")]
    property has_more : Bool = false
  end

  struct Thread
    include JSON::Serializable

    property id : String
    property object : String
    @[JSON::Field(key: "created_at")]
    property created_at : Int64
    property metadata : Hash(String, String)? = nil
    @[JSON::Field(key: "tool_resources")]
    property tool_resources : Json? = nil
  end

  struct ThreadMessage
    include JSON::Serializable

    property id : String
    property object : String
    @[JSON::Field(key: "created_at")]
    property created_at : Int64
    @[JSON::Field(key: "thread_id")]
    property thread_id : String? = nil
    property role : String? = nil
    property content : Json? = nil
    property metadata : Hash(String, String)? = nil
  end

  struct ThreadMessageList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(ThreadMessage)
    @[JSON::Field(key: "first_id")]
    property first_id : String? = nil
    @[JSON::Field(key: "last_id")]
    property last_id : String? = nil
    @[JSON::Field(key: "has_more")]
    property has_more : Bool = false
  end

  struct ThreadRun
    include JSON::Serializable

    property id : String
    property object : String
    @[JSON::Field(key: "created_at")]
    property created_at : Int64
    @[JSON::Field(key: "thread_id")]
    property thread_id : String
    @[JSON::Field(key: "assistant_id")]
    property assistant_id : String? = nil
    property status : String? = nil
    @[JSON::Field(key: "required_action")]
    property required_action : Json? = nil
    property usage : Usage? = nil
    property metadata : Hash(String, String)? = nil
  end

  struct ThreadRunList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(ThreadRun)
    @[JSON::Field(key: "first_id")]
    property first_id : String? = nil
    @[JSON::Field(key: "last_id")]
    property last_id : String? = nil
    @[JSON::Field(key: "has_more")]
    property has_more : Bool = false
  end

  struct ThreadRunStep
    include JSON::Serializable

    property id : String
    property object : String
    @[JSON::Field(key: "created_at")]
    property created_at : Int64
    property status : String? = nil
    property type : String? = nil
    @[JSON::Field(key: "run_id")]
    property run_id : String? = nil
    @[JSON::Field(key: "thread_id")]
    property thread_id : String? = nil
    property usage : Usage? = nil
    property step_details : Json? = nil
  end

  struct ThreadRunStepList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(ThreadRunStep)
    @[JSON::Field(key: "first_id")]
    property first_id : String? = nil
    @[JSON::Field(key: "last_id")]
    property last_id : String? = nil
    @[JSON::Field(key: "has_more")]
    property has_more : Bool = false
  end

  struct VectorStore
    include JSON::Serializable

    property id : String
    property object : String
    @[JSON::Field(key: "created_at")]
    property created_at : Int64
    property name : String? = nil
    @[JSON::Field(key: "usage_bytes")]
    property usage_bytes : Int64? = nil
    property metadata : Hash(String, String)? = nil
  end

  struct VectorStoreList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(VectorStore)
    @[JSON::Field(key: "first_id")]
    property first_id : String? = nil
    @[JSON::Field(key: "last_id")]
    property last_id : String? = nil
    @[JSON::Field(key: "has_more")]
    property has_more : Bool = false
  end

  struct Batch
    include JSON::Serializable

    property id : String
    property object : String
    property status : String? = nil
    @[JSON::Field(key: "output_file_id")]
    property output_file_id : String? = nil
  end

  struct BatchList
    include JSON::Serializable

    property object : String? = nil
    property data : Array(Batch)
    @[JSON::Field(key: "first_id")]
    property first_id : String? = nil
    @[JSON::Field(key: "last_id")]
    property last_id : String? = nil
    @[JSON::Field(key: "has_more")]
    property has_more : Bool = false
  end

  struct ResponseObject
    include JSON::Serializable

    property id : String
    property object : String
    property status : String? = nil
    property output : Json? = nil
  end

  struct DeletionStatus
    include JSON::Serializable

    property id : String
    property object : String
    property deleted : Bool
  end

  # Request payload for /v1/chat/completions
  struct ChatCompletionRequest
    include JSON::Serializable

    # Chat request message payload (role + content string or JSON content object).
    struct ChatMessagePayload
      include JSON::Serializable

      def initialize(@role : String, @content : Json | String)
      end

      # Role of the message author (user/assistant/system/tool).
      property role : String

      # Content can be a plain string or a JSON object/array (e.g., multimodal parts).
      property content : Json | String
    end

    # Convenience tuple type for simple text-only messages.
    alias MessageTuple = NamedTuple(role: String, content: String)

    def initialize(
      @model : String,
      @messages : Array(ChatMessagePayload),
      @temperature : Float64? = nil,
      @top_p : Float64? = nil,
      @n : Int32? = nil,
      @stream : Bool? = nil,
      @max_tokens : Int32? = nil,
      @presence_penalty : Float64? = nil,
      @frequency_penalty : Float64? = nil,
      @seed : Int32? = nil,
      @user : String? = nil,
      @tools : Array(Json)? = nil,
      @tool_choice : Json? = nil,
      @response_format : Json? = nil,
      @parallel_tool_calls : Bool? = nil
    ); end

    # ID of the model to use.
    property model : String

    # Conversation messages in OpenAI chat format (typed payloads).
    property messages : Array(ChatMessagePayload)

    # Sampling temperature between 0 and 2; higher is more random.
    property temperature : Float64? = nil

    # nucleus sampling probability mass; alternative to temperature.
    @[JSON::Field(key: "top_p")]
    property top_p : Float64? = nil

    # How many completions to generate for each input message.
    @[JSON::Field(key: "n")]
    property n : Int32? = nil

    # If true, stream responses; prefer using chat_completions_stream for streaming.
    property stream : Bool? = nil

    # Maximum number of tokens to generate.
    @[JSON::Field(key: "max_tokens")]
    property max_tokens : Int32? = nil

    # Penalize new tokens based on their presence in the text so far.
    @[JSON::Field(key: "presence_penalty")]
    property presence_penalty : Float64? = nil

    # Penalize new tokens based on frequency.
    @[JSON::Field(key: "frequency_penalty")]
    property frequency_penalty : Float64? = nil

    # Optional seed for deterministic sampling.
    property seed : Int32? = nil

    # User identifier for abuse monitoring.
    property user : String? = nil

    # Tool definitions for function calling (array of objects per OpenAI spec).
    property tools : Array(Json)? = nil

    # Controls how tools are called: "none", "auto", "required", or specific tool choice object.
    @[JSON::Field(key: "tool_choice")]
    property tool_choice : Json? = nil

    # Optional system-level settings like response_format.
    @[JSON::Field(key: "response_format")]
    property response_format : Json? = nil

    # Optional parallel tool calls toggle.
    @[JSON::Field(key: "parallel_tool_calls")]
    property parallel_tool_calls : Bool? = nil
  end

  # Request payload for /v1/embeddings
  struct EmbeddingsRequest
    include JSON::Serializable

    def initialize(@model : String, @input : String | Array(String), @user : String? = nil); end

    # ID of the model to use for embedding.
    property model : String

    # Input text to embed (string or array of strings/tokens).
    property input : String | Array(String)

    # User identifier for abuse monitoring.
    property user : String? = nil
  end

  # Request payload for /v1/completions (legacy)
  struct CompletionRequest
    include JSON::Serializable

    def initialize(
      @model : String,
      @prompt : String | Array(String),
      @max_tokens : Int32? = nil,
      @temperature : Float64? = nil,
      @top_p : Float64? = nil,
      @n : Int32? = nil,
      @stop : String | Array(String) | Nil = nil,
      @user : String? = nil
    ); end

    # ID of the model to use.
    property model : String

    # Prompt string or array of prompts.
    property prompt : String | Array(String)

    # Maximum number of tokens to generate.
    @[JSON::Field(key: "max_tokens")]
    property max_tokens : Int32? = nil

    # Sampling temperature between 0 and 2.
    property temperature : Float64? = nil

    # nucleus sampling probability mass.
    @[JSON::Field(key: "top_p")]
    property top_p : Float64? = nil

    # Number of completions to generate.
    @[JSON::Field(key: "n")]
    property n : Int32? = nil

    # Stop sequences that truncate generation.
    property stop : String | Array(String) | Nil = nil

    # User identifier for abuse monitoring.
    property user : String? = nil
  end

  # Request payload for /v1/images/generations
  struct ImagesGenerateRequest
    include JSON::Serializable

    def initialize(
      @prompt : String,
      @model : String? = nil,
      @n : Int32? = nil,
      @size : String? = nil,
      @response_format : String? = nil,
      @user : String? = nil
    ); end

    # Text prompt to generate the image.
    property prompt : String

    # ID of the model to use.
    property model : String? = nil

    # Number of images to generate (1-10).
    @[JSON::Field(key: "n")]
    property n : Int32? = nil

    # Size of the generated image, e.g., "1024x1024".
    property size : String? = nil

    # Response format: "url" or "b64_json".
    @[JSON::Field(key: "response_format")]
    property response_format : String? = nil

    # Optional user identifier.
    property user : String? = nil
  end

  # Request payload for /v1/images/edits (multipart helpers use these fields)
  struct ImageEditRequest
    include JSON::Serializable

    def initialize(
      @prompt : String? = nil,
      @model : String? = nil,
      @n : Int32? = nil,
      @size : String? = nil,
      @response_format : String? = nil,
      @user : String? = nil,
      @mask_io : IO? = nil,
      @mask_filename : String? = nil
    ); end

    # Text prompt that describes the edit.
    property prompt : String? = nil

    # ID of the model to use.
    property model : String? = nil

    # Number of images to generate (1-10).
    @[JSON::Field(key: "n")]
    property n : Int32? = nil

    # Size of the generated image.
    property size : String? = nil

    # Response format: "url" or "b64_json".
    @[JSON::Field(key: "response_format")]
    property response_format : String? = nil

    # Optional user identifier.
    property user : String? = nil

    # Optional mask IO (not serialized; used in multipart body).
    @[JSON::Field(ignore: true)]
    property mask_io : IO? = nil

    # Optional mask filename (not serialized).
    @[JSON::Field(ignore: true)]
    property mask_filename : String? = nil
  end

  # Request payload for /v1/images/variations
  struct ImageVariationRequest
    include JSON::Serializable

    def initialize(
      @model : String? = nil,
      @n : Int32? = nil,
      @size : String? = nil,
      @response_format : String? = nil,
      @user : String? = nil
    ); end

    # ID of the model to use.
    property model : String? = nil

    # Number of images to generate (1-10).
    @[JSON::Field(key: "n")]
    property n : Int32? = nil

    # Size of the generated image.
    property size : String? = nil

    # Response format: "url" or "b64_json".
    @[JSON::Field(key: "response_format")]
    property response_format : String? = nil

    # Optional user identifier.
    property user : String? = nil
  end

  # Request payload for /v1/moderations
  struct ModerationRequest
    include JSON::Serializable

    def initialize(@input : String | Array(String), @model : String? = nil); end

    # Input text to classify.
    property input : String | Array(String)

    # ID of the model to use.
    property model : String? = nil
  end

  # Request payload for /v1/audio/transcriptions (options; file is separate)
  struct TranscriptionRequest
    include JSON::Serializable

    def initialize(
      @model : String,
      @language : String? = nil,
      @prompt : String? = nil,
      @response_format : String? = nil,
      @temperature : Float64? = nil
    ); end

    # ID of the model to use (e.g., "gpt-4o-audio-preview").
    property model : String

    # Optional language hint.
    property language : String? = nil

    # Optional prompt to guide the model.
    property prompt : String? = nil

    # Desired response format (json, text, srt, verbose_json, vtt).
    @[JSON::Field(key: "response_format")]
    property response_format : String? = nil

    # Sampling temperature between 0 and 1.
    property temperature : Float64? = nil
  end

  # Request payload for /v1/audio/translations (options; file is separate)
  struct TranslationRequest
    include JSON::Serializable

    def initialize(
      @model : String,
      @prompt : String? = nil,
      @response_format : String? = nil,
      @temperature : Float64? = nil
    ); end

    # ID of the model to use.
    property model : String

    # Optional prompt to guide the model.
    property prompt : String? = nil

    # Desired response format (json, text, srt, verbose_json, vtt).
    @[JSON::Field(key: "response_format")]
    property response_format : String? = nil

    # Sampling temperature between 0 and 1.
    property temperature : Float64? = nil
  end

  # Request payload for /v1/audio/speech
  struct SpeechRequest
    include JSON::Serializable

    def initialize(
      @model : String,
      @input : String,
      @voice : String? = nil,
      @response_format : String? = nil,
      @speed : Float64? = nil
    ); end

    # ID of the model to use.
    property model : String

    # Text to synthesize into audio.
    property input : String

    # Voice preset, e.g., "alloy".
    property voice : String? = nil

    # Audio format, e.g., "mp3", "wav".
    @[JSON::Field(key: "response_format")]
    property response_format : String? = nil

    # Playback speed (0.25 - 4.0).
    property speed : Float64? = nil
  end

  # Request payload for /v1/files (options; file is separate)
  struct UploadFileRequest
    include JSON::Serializable

    def initialize(@purpose : String); end

    # Purpose of the file (e.g., "fine-tune", "assistants").
    property purpose : String
  end

  # Request payload for /v1/fine_tuning/jobs
  struct CreateFineTuningJobRequest
    include JSON::Serializable

    def initialize(
      @model : String,
      @training_file : String,
      @validation_file : String? = nil,
      @hyperparameters : Json? = nil
    ); end

    # Base model to fine-tune.
    property model : String

    # Training file id (uploaded via files API).
    @[JSON::Field(key: "training_file")]
    property training_file : String

    # Optional validation file id.
    @[JSON::Field(key: "validation_file")]
    property validation_file : String? = nil

    # Hyperparameters object per API (learning_rate_multiplier, n_epochs, batch_size).
    property hyperparameters : Json? = nil
  end

  # Request payload for /v1/assistants
  struct CreateAssistantRequest
    include JSON::Serializable

    def initialize(
      @model : String,
      @name : String? = nil,
      @description : String? = nil,
      @instructions : String? = nil,
      @tools : Array(Json)? = nil,
      @tool_resources : Json? = nil,
      @metadata : Hash(String, String)? = nil,
      @temperature : Float64? = nil,
      @top_p : Float64? = nil,
      @response_format : Json? = nil
    ); end

    # ID of the model to use.
    property model : String

    # Human-readable name for the assistant.
    property name : String? = nil

    # Description of the assistant.
    property description : String? = nil

    # System instructions for the assistant.
    property instructions : String? = nil

    # Tools the assistant can use (code_interpreter, retrieval, functions) as JSON objects.
    property tools : Array(Json)? = nil

    # Tool resources block per API (e.g., file_ids for retrieval).
    @[JSON::Field(key: "tool_resources")]
    property tool_resources : Json? = nil

    # Key/value metadata (strings only).
    property metadata : Hash(String, String)? = nil

    # Sampling temperature.
    property temperature : Float64? = nil

    # nucleus sampling probability mass.
    @[JSON::Field(key: "top_p")]
    property top_p : Float64? = nil

    # Response format controls JSON/text output.
    @[JSON::Field(key: "response_format")]
    property response_format : Json? = nil
  end

  # Request payload for modifying an assistant
  struct ModifyAssistantRequest
    include JSON::Serializable

    def initialize(
      @model : String? = nil,
      @name : String? = nil,
      @description : String? = nil,
      @instructions : String? = nil,
      @tools : Array(Json)? = nil,
      @tool_resources : Json? = nil,
      @metadata : Hash(String, String)? = nil,
      @temperature : Float64? = nil,
      @top_p : Float64? = nil,
      @response_format : Json? = nil
    ); end

    # ID of the model to use (optional update).
    property model : String? = nil

    # Human-readable name for the assistant.
    property name : String? = nil

    # Description of the assistant.
    property description : String? = nil

    # System instructions for the assistant.
    property instructions : String? = nil

    # Tools the assistant can use.
    property tools : Array(Json)? = nil

    # Tool resources block per API.
    @[JSON::Field(key: "tool_resources")]
    property tool_resources : Json? = nil

    # Key/value metadata (strings only).
    property metadata : Hash(String, String)? = nil

    # Sampling temperature.
    property temperature : Float64? = nil

    # nucleus sampling probability mass.
    @[JSON::Field(key: "top_p")]
    property top_p : Float64? = nil

    # Response format controls JSON/text output.
    @[JSON::Field(key: "response_format")]
    property response_format : Json? = nil
  end

  # Query params for listing assistants
  struct ListAssistantsParams
    include JSON::Serializable

    def initialize; end

    # Max number of items to return (1-100).
    property limit : Int32? = nil

    # Sort order by created_at: "asc" or "desc".
    property order : String? = nil

    # Cursor for next page.
    property after : String? = nil

    # Cursor for previous page.
    property before : String? = nil
  end

  # Request payload for /v1/threads
  struct CreateThreadRequest
    include JSON::Serializable

    def initialize; end

    # Optional initial messages for the thread.
    property messages : Array(Json)? = nil

    # Optional tool resources available to the thread.
    @[JSON::Field(key: "tool_resources")]
    property tool_resources : Json? = nil

    # Key/value metadata.
    property metadata : Hash(String, String)? = nil
  end

  # Request payload for /v1/threads/{thread_id}/messages
  struct CreateMessageRequest
    include JSON::Serializable

    def initialize(@role : String, @content : Json, @metadata : Hash(String, String)? = nil); end

    # Role of the message author (user/assistant/tool).
    property role : String

    # Content payload; can be text or array per OpenAI spec.
    property content : Json

    # Key/value metadata.
    property metadata : Hash(String, String)? = nil
  end

  # Query params for listing messages in a thread
  struct ListMessagesParams
    include JSON::Serializable

    def initialize; end

    # Max number of items to return (1-100).
    property limit : Int32? = nil

    # Sort order by created_at: "asc" or "desc".
    property order : String? = nil

    # Cursor for next page.
    property after : String? = nil

    # Cursor for previous page.
    property before : String? = nil

    # Filter by run_id (optional).
    @[JSON::Field(key: "run_id")]
    property run_id : String? = nil
  end

  # Request payload for /v1/threads/{thread_id}/runs
  struct CreateRunRequest
    include JSON::Serializable

    def initialize(
      @assistant_id : String,
      @model : String? = nil,
      @instructions : String? = nil,
      @tools : Array(Json)? = nil,
      @response_format : Json? = nil,
      @metadata : Hash(String, String)? = nil
    ); end

    # Assistant id to execute the run.
    @[JSON::Field(key: "assistant_id")]
    property assistant_id : String

    # Override model for this run.
    property model : String? = nil

    # Additional instructions.
    property instructions : String? = nil

    # Tools array for this run.
    property tools : Array(Json)? = nil

    # Response format override.
    @[JSON::Field(key: "response_format")]
    property response_format : Json? = nil

    # Key/value metadata.
    property metadata : Hash(String, String)? = nil
  end

  # Request payload for /v1/threads/runs (create thread + run)
  struct CreateThreadAndRunRequest
    include JSON::Serializable

    def initialize(
      @assistant_id : String,
      @thread : CreateThreadRequest? = nil,
      @model : String? = nil,
      @instructions : String? = nil,
      @tools : Array(Json)? = nil,
      @response_format : Json? = nil,
      @metadata : Hash(String, String)? = nil
    ); end

    # Assistant id to execute the run.
    @[JSON::Field(key: "assistant_id")]
    property assistant_id : String

    # Thread definition to create.
    property thread : CreateThreadRequest? = nil

    # Override model for this run.
    property model : String? = nil

    # Additional instructions.
    property instructions : String? = nil

    # Tools array for this run.
    property tools : Array(Json)? = nil

    # Response format override.
    @[JSON::Field(key: "response_format")]
    property response_format : Json? = nil

    # Key/value metadata.
    property metadata : Hash(String, String)? = nil
  end

  # Request payload for submitting tool outputs to a run
  struct SubmitToolOutputsRequest
    include JSON::Serializable

    def initialize(@tool_outputs : Array(Json), @stream : Bool? = nil); end

    # Array of tool output objects per spec (tool_call_id, output).
    @[JSON::Field(key: "tool_outputs")]
    property tool_outputs : Array(Json)

    # Flag to mark completion after submission.
    property stream : Bool? = nil
  end

  # Request payload for /v1/vector_stores
  struct CreateVectorStoreRequest
    include JSON::Serializable

    def initialize(@name : String? = nil, @metadata : Hash(String, String)? = nil); end

    # Human-readable name of the vector store.
    property name : String? = nil

    # Key/value metadata.
    property metadata : Hash(String, String)? = nil
  end

  # Request payload for /v1/batches
  struct CreateBatchRequest
    include JSON::Serializable

    def initialize(@input_file_id : String, @endpoint : String, @completion_window : String); end

    # ID of an uploaded input file containing requests.
    @[JSON::Field(key: "input_file_id")]
    property input_file_id : String

    # Endpoint to invoke for each request in the batch (e.g., "/v1/chat/completions").
    property endpoint : String

    # Completion window, e.g., "24h".
    @[JSON::Field(key: "completion_window")]
    property completion_window : String
  end

  # Request payload for /v1/responses
  struct CreateResponseRequest
    include JSON::Serializable

    def initialize(
      @model : String,
      @input : Array(Json),
      @metadata : Hash(String, String)? = nil,
      @response_format : Json? = nil
    ); end

    # ID of the model to use.
    property model : String

    # Input items for the response API (array of input objects per spec).
    property input : Array(Json)

    # Response instructions / metadata block.
    property metadata : Hash(String, String)? = nil

    # Response format controls JSON/text output.
    @[JSON::Field(key: "response_format")]
    property response_format : Json? = nil
  end

  # Request payload for appending input items to a streaming response
  struct AppendResponseInputRequest
    include JSON::Serializable

    def initialize(@input : Array(Json)); end

    # Input items to append to an existing response.
    property input : Array(Json)
  end

  # A very small wrapper for untyped access when needed
  alias Json = JSON::Any
end
