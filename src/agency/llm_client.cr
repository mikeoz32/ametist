require "../openai/client"
require "./protocol"

module Agency
  # Simple wrapper around the OpenAI client for chat completions.
  # It isolates the OpenAI dependency and provides a single method used by the runtime.
  class LLMClient
    @client : OpenAI::Client
    @api_key : String
    @base_url : String

    # Initialize with an API key and optional base URL (OpenAI-compatible).
    # For local models, pass base_url like "http://localhost:11434/v1" and api_key can be empty.
    def initialize(api_key : String = "", base_url : String = "https://api.openai.com")
      @api_key = api_key
      @base_url = base_url
      @client = OpenAI::Client.new(api_key, base_url)
    end

    # Perform a chat completion using an array of structured messages and tool schema.
    # Returns the assistant's reply as a raw string (expected to be JSON per Protocol).
    def chat(messages : Array(Agency::Message), tools : Array(Agency::ToolSpec), model : String = "gpt-3.5-turbo") : String
      system_prompt = Agency::Protocol.system_prompt(tools)
      payload_messages = [] of OpenAI::ChatCompletionRequest::ChatMessagePayload
      payload_messages << OpenAI::ChatCompletionRequest::ChatMessagePayload.new("system", system_prompt)

      messages.each do |msg|
        role = case msg.role
               when Role::System then "system"
               when Role::User then "user"
               when Role::Assistant then "assistant"
               when Role::Tool then "user"
               else "assistant"
               end

        content = msg.content
        if msg.role == Role::Tool
          tool_name = msg.name || "tool"
          tool_id = msg.tool_call_id || "unknown"
          content = "TOOL[#{tool_name} id=#{tool_id}]: #{msg.content}"
        end

        payload_messages << OpenAI::ChatCompletionRequest::ChatMessagePayload.new(role, content)
      end

      if @api_key == "dummy-key"
        last_user = messages.reverse.find { |m| m.role == Role::User }.try(&.content) || ""
        return {"type" => "final", "content" => "(LLM) Simulated response for: #{last_user}"}.to_json
      end

      payload = OpenAI::ChatCompletionRequest.new(model, payload_messages)
      begin
        response = @client.chat_completions(payload)
        if response.choices.empty?
          {"type" => "final", "content" => "(LLM) empty response"}.to_json
        else
          response.choices.first.message.content
        end
      rescue ex : Exception
        {"type" => "final", "content" => "(LLM) error: #{ex.message}"}.to_json
      end
    end
  end
end
