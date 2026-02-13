require "../src/movie"

alias Streams = Movie::Streams::Typed
alias Elem = Int32

pipeline = Streams.build_collecting_pipeline(
  Elem,
  Streams::ManualSource(Elem).new,
  [
    Streams::MapFlow(Elem).new { |v| v * 2 },
    Streams::FilterFlow(Elem).new { |v| v.even? },
    Streams::TakeFlow(Elem).new(3u64),
  ],
  initial_demand: 3u64
)

source = pipeline.source
out = pipeline.out_channel.not_nil!

source << Streams::Produce(Elem).new(1)
source << Streams::Produce(Elem).new(2)
source << Streams::Produce(Elem).new(3)
source << Streams::Produce(Elem).new(4)
source << Streams::Produce(Elem).new(5)
source << Streams::OnComplete(Elem).new

3.times do
  puts "got #{out.receive}"
end

# Wait for completion to ensure the pipeline stops cleanly.
pipeline.completion.await
