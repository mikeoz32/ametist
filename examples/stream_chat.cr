require "json"
require "./../src/openai/client"

# Streaming chat completion example.
# Usage: OPENAI_API_KEY=sk-... crystal run examples/stream_chat.cr
# Note: Requires a model that supports streaming (e.g., "gpt-4o").

api_key = ENV["OPENAI_API_KEY"]?
abort "Please set OPENAI_API_KEY" unless api_key

client = OpenAI::Client.new(api_key)

messages = [OpenAI::ChatCompletionRequest::ChatMessagePayload.new("user", "Write a short poem about Crystal.")]
payload = OpenAI::ChatCompletionRequest.new(model: "gpt-4o", messages: messages, temperature: 0.7)

STDOUT.sync = true
print "Streaming: "

client.chat.completions_stream(payload) do |line|
  # Each line is a raw JSON delta string from the SSE stream.
  # Parse and extract partial content tokens if present.
  data = line
  if (choices_any = data.choices) && !choices_any.empty?
    if delta = choices_any.first.delta
      if content = delta.content
        puts content
      end
    end
  end
end

puts "\n\n[DONE]"
