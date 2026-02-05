require "../../movie"
require "../../openai/client"

module Agency
  class EmbedderError < Exception
    getter cause : Exception?

    def initialize(message : String, @cause : Exception? = nil)
      super(message)
    end
  end

  class EmbedderExtension < Movie::Extension
    getter model : String

    def initialize(@system : Movie::AbstractActorSystem, @client : OpenAI::Client, @model : String)
    end

    def stop
      # No-op; OpenAI client is stateless.
    end

    def embed(
      texts : Array(String),
      model : String? = nil,
      user : String? = nil,
      timeout : Time::Span? = nil
    ) : Movie::Future(Array(Array(Float32)))
      execute_with_wrap(timeout) do
        payload = OpenAI::EmbeddingsRequest.new(model || @model, texts, user)
        response = @client.embeddings(payload)
        response.data
          .sort_by(&.index)
          .map { |item| item.embedding.map(&.to_f32) }
      end
    end

    def embed(
      text : String,
      model : String? = nil,
      user : String? = nil,
      timeout : Time::Span? = nil
    ) : Movie::Future(Array(Float32))
      execute_with_wrap(timeout) do
        payload = OpenAI::EmbeddingsRequest.new(model || @model, text, user)
        response = @client.embeddings(payload)
        first = response.data.sort_by(&.index).first?
        first ? first.embedding.map(&.to_f32) : [] of Float32
      end
    end

    private def execute_with_wrap(timeout : Time::Span?, &block : -> T) : Movie::Future(T) forall T
      exec = Movie::Execution.get(@system)
      promise = Movie::Promise(T).new
      future = exec.execute(timeout) { block.call }
      future.on_success { |value| promise.try_success(value) }
      future.on_failure { |error| promise.try_failure(EmbedderError.new("Embedder failed", error)) }
      future.on_cancel { promise.try_failure(EmbedderError.new("Embedder cancelled")) }
      promise.future
    end
  end

  class EmbedderExtensionId < Movie::ExtensionId(EmbedderExtension)
    def create(system : Movie::AbstractActorSystem) : EmbedderExtension
      base_url = resolve_base_url(system)
      api_key = resolve_api_key(system, base_url)
      model = resolve_model(system)
      client = OpenAI::Client.new(api_key, base_url)
      EmbedderExtension.new(system, client, model)
    end

    private def resolve_api_key(system : Movie::AbstractActorSystem, base_url : String) : String
      key = ""
      unless system.config.empty?
        key = system.config.get_string("agency.embedder.api_key", "")
        if key.empty?
          key = system.config.get_string("agency.llm.api_key", "")
        end
      end
      if key.empty?
        key = ENV["OPENAI_API_KEY"]? || ""
      end
      if key.empty? && base_url.includes?("api.openai.com")
        raise "Missing OpenAI API key for EmbedderExtension"
      end
      key
    end

    private def resolve_base_url(system : Movie::AbstractActorSystem) : String
      url = ""
      unless system.config.empty?
        url = system.config.get_string("agency.embedder.base_url", "")
        if url.empty?
          url = system.config.get_string("agency.llm.base_url", "")
        end
      end
      if url.empty?
        url = ENV["OPENAI_BASE_URL"]? || ENV["OPENAI_API_BASE"]? || ""
      end
      url.empty? ? "https://api.openai.com" : url
    end

    private def resolve_model(system : Movie::AbstractActorSystem) : String
      return "text-embedding-3-small" if system.config.empty?
      model = system.config.get_string("agency.embedder.model", "")
      model = system.config.get_string("agency.llm.model", "") if model.empty?
      model.empty? ? "text-embedding-3-small" : model
    end
  end
end
