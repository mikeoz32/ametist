require "../src/movie"

class FailingWorker < Movie::AbstractBehavior(Int32)
  def receive(message, context)
    raise "boom" if message == 1
    Movie::Behaviors(Int32).same
  end
end

one_for_one = Movie::SupervisionConfig.new(
  strategy: Movie::SupervisionStrategy::RESTART,
  scope: Movie::SupervisionScope::ONE_FOR_ONE,
  max_restarts: 2,
  within: 1.second,
  backoff_min: 20.milliseconds,
  backoff_max: 200.milliseconds,
  backoff_factor: 2.0,
  jitter: 0.1,
)

system = Movie::ActorSystem(Int32).new(Movie::Behaviors(Int32).same, Movie::RestartStrategy::RESTART, one_for_one)
worker = system.spawn(FailingWorker.new, Movie::RestartStrategy::RESTART, one_for_one)

all_for_one = Movie::SupervisionConfig.new(
  strategy: Movie::SupervisionStrategy::RESTART,
  scope: Movie::SupervisionScope::ALL_FOR_ONE,
  max_restarts: 1,
  within: 200.milliseconds,
  backoff_min: 30.milliseconds,
  backoff_max: 500.milliseconds,
  backoff_factor: 2.0,
  jitter: 0.0,
)

parent = system.spawn(Movie::Behaviors(Int32).same, Movie::RestartStrategy::RESTART, all_for_one)
child_a = system.spawn(FailingWorker.new, Movie::RestartStrategy::RESTART, all_for_one)
child_b = system.spawn(FailingWorker.new, Movie::RestartStrategy::RESTART, all_for_one)

# Trigger failures to see supervision in action
worker << 1
child_a << 1
