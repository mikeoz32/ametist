require "../src/movie"

alias Streams = Movie::Streams

pipeline = Streams.build_collecting_pipeline(
  Streams::ManualSource.new,
  [
    Streams::MapFlow.new { |v| v.as(Int32) * 2 },
    Streams::FilterFlow.new { |v| v.as(Int32).even? },
    Streams::TakeFlow.new(3u64),
  ],
  initial_demand: 3u64
)

source = pipeline.source
out = pipeline.out_channel.not_nil!

source << Streams::Produce.new(1)
source << Streams::Produce.new(2)
source << Streams::Produce.new(3)
source << Streams::Produce.new(4)
source << Streams::Produce.new(5)
source << Streams::OnComplete.new

3.times do
  puts "got #{out.receive}"
end

# Wait for completion to ensure the pipeline stops cleanly.
pipeline.completion.await
