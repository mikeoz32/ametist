# OpenAI Client (Crystal)

Typed wrapper over the OpenAI REST API. Responses deserialize via `JSON::Serializable` structs (see [src/openai/types.cr](../src/openai/types.cr)).

## Setup

```crystal
# From project root (adjust path if vendored differently)
require "./src/openai/client"

client = OpenAI::Client.new(ENV["OPENAI_API_KEY"] || "sk-...")
```

## Models

```crystal
list = client.models             # => OpenAI::ModelsList
model = client.retrieve_model("gpt-4o")
```

## Chat Completions

```crystal
resp = client.chat_completions({
	"model" => "gpt-4o",
	"messages" => [
		{"role" => "user", "content" => "Say hi"}
	]
})
puts resp.choices.first.message.content

# Streaming (SSE): yields raw `data:` lines (already stripped)
client.chat_completions_stream({"model" => "gpt-4o", "messages" => [{"role" => "user", "content" => "Stream"}]}) do |chunk|
	puts "chunk: #{chunk}"
end
```

## Legacy Completions

```crystal
legacy = client.completions({"model" => "gpt-3.5-turbo-instruct", "prompt" => "Hello"})
```

## Embeddings

```crystal
emb = client.embeddings("text-embedding-3-small", "hello")
vector = emb.data.first.embedding
```

## Images

```crystal
# Generate
img = client.images_generate({"model" => "gpt-image-1", "prompt" => "A calm lake"})

# Edit (requires source image IO, optional mask)
File.open("image.png") do |io|
	edit = client.images_edit(io, "image.png", {"prompt" => "add a boat"})
end

# Variations
File.open("image.png") do |io|
	variations = client.images_variations(io, "image.png", {"n" => 1})
end
```

## Moderations

```crystal
mod = client.moderation({"model" => "omni-moderation-latest", "input" => "..."})
puts mod.results.first.flagged
```

## Audio

```crystal
# Transcription
File.open("audio.mp3") do |io|
	t = client.transcription(io, "audio.mp3", "gpt-4o-transcribe")
	puts t.text
end

# Translation to English
File.open("audio.mp3") do |io|
	tr = client.translation(io, "audio.mp3", "gpt-4o-transcribe")
end

# Text-to-speech (returns binary audio)
audio_bin = client.speech({"model" => "gpt-4o-mini-tts", "input" => "Hello"})
```

## Files

```crystal
File.open("train.jsonl") do |io|
	uploaded = client.upload_file(io, "train.jsonl", "fine-tune")
end

files = client.list_files
meta = client.retrieve_file(files.data.first.id)
client.delete_file(meta.id)

# Download (binary string)
content = client.download_file(meta.id)
```

## Fine-tuning

```crystal
job = client.create_fine_tuning_job({"model" => "gpt-4o-mini", "training_file" => "file-123"})
jobs = client.list_fine_tuning_jobs
job = client.retrieve_fine_tuning_job(job.id)
client.cancel_fine_tuning_job(job.id)
```

## Errors

Network / HTTP errors raise `OpenAI::ApiError` with `status` and `body`.

```crystal
begin
	client.chat_completions({})
rescue OpenAI::ApiError => e
	puts e.status
	puts e.body
end
```

## Custom HTTP adapter

Pass any object implementing `OpenAI::HttpClient#request` to inject retries or logging.

```crystal
client = OpenAI::Client.new(api_key, http_client: MyAdapter.new)
```

## Running specs for this client only

```bash
crystal spec spec/openai_spec.cr -Dpreview_mt -Dreview_mt -Dexecution_context
```
