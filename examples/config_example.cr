require "../src/movie"

# Config Example
# ==============
# Demonstrates configuration-based ActorSystem setup.
#
# Run with:
#   crystal run examples/config_example.cr -Dpreview_mt -Dexecution_context
#
# Or with environment overrides:
#   MOVIE_NAME=production MOVIE_REMOTING_PORT=9001 crystal run examples/config_example.cr -Dpreview_mt -Dexecution_context

# Quiet down the logs
Log.setup do |c|
  c.bind "*", :warn, Log::IOBackend.new
end

puts "=" * 60
puts "Movie Actor Config Example"
puts "=" * 60
puts

# --- Example 1: Default Config ---
puts "-" * 60
puts "Example 1: Default Configuration Values"
puts "-" * 60

defaults = Movie::ActorSystemConfig.default
puts "Default config paths:"
puts "  name:                    '#{defaults.get_string("name")}' (empty = auto-generate)"
puts "  supervision.strategy:    #{defaults.get_string("supervision.strategy")}"
puts "  supervision.scope:       #{defaults.get_string("supervision.scope")}"
puts "  supervision.max-restarts: #{defaults.get_int("supervision.max-restarts")}"
puts "  supervision.within:      #{defaults.get_duration("supervision.within")}"
puts "  remoting.enabled:        #{defaults.get_bool("remoting.enabled")}"
puts "  remoting.host:           #{defaults.get_string("remoting.host")}"
puts "  remoting.port:           #{defaults.get_int("remoting.port")}"
puts

# --- Example 2: Programmatic Config ---
puts "-" * 60
puts "Example 2: Programmatic Configuration"
puts "-" * 60

config = Movie::Config.builder
  .set("name", "my-system")
  .set("supervision.strategy", "restart")
  .set("supervision.max-restarts", 5)
  .set_duration("supervision.within", 10.seconds)
  .set("remoting.enabled", false)
  .build

# Create system with config
system1 = Movie::ActorSystem(String).new(
  Movie::Behaviors(String).same,
  config
)

puts "Created system from config:"
puts "  Name: #{system1.name}"
puts "  Remoting enabled: #{system1.remoting_enabled?}"
puts

# --- Example 3: YAML Config ---
puts "-" * 60
puts "Example 3: YAML Configuration"
puts "-" * 60

yaml_config = Movie::Config.from_yaml(<<-YAML)
  name: yaml-system
  supervision:
    strategy: restart
    max-restarts: 10
    within: 30s
    backoff:
      min: 100ms
      max: 5s
      factor: 2.5
  remoting:
    enabled: true
    host: 0.0.0.0
    port: 9000
YAML

# Merge with defaults to get all values
full_config = yaml_config.with_fallback(Movie::ActorSystemConfig.default)

puts "YAML config values:"
puts "  name:                  #{full_config.get_string("name")}"
puts "  supervision.strategy:  #{full_config.get_string("supervision.strategy")}"
puts "  supervision.max-restarts: #{full_config.get_int("supervision.max-restarts")}"
puts "  supervision.within:    #{full_config.get_duration("supervision.within")}"
puts "  supervision.backoff.min: #{full_config.get_duration("supervision.backoff.min")}"
puts "  supervision.backoff.max: #{full_config.get_duration("supervision.backoff.max")}"
puts "  remoting.enabled:      #{full_config.get_bool("remoting.enabled")}"
puts "  remoting.port:         #{full_config.get_int("remoting.port")}"
puts

# Create system with YAML config (remoting auto-enabled)
system2 = Movie::ActorSystem(String).new(
  Movie::Behaviors(String).same,
  full_config
)

puts "Created system from YAML config:"
puts "  Name: #{system2.name}"
puts "  Remoting enabled: #{system2.remoting_enabled?}"
if remote = system2.remote
  puts "  Listening on: #{remote.address}"
end
puts

# --- Example 4: Environment Overrides ---
puts "-" * 60
puts "Example 4: Environment Variable Overrides"
puts "-" * 60

# Check if any MOVIE_* env vars are set
env_vars = ENV.to_h.select { |k, _| k.starts_with?("MOVIE_") }
if env_vars.empty?
  puts "No MOVIE_* environment variables set."
  puts "Try running with:"
  puts "  MOVIE_NAME=production MOVIE_REMOTING_PORT=9001 crystal run ..."
else
  puts "Found MOVIE_* environment variables:"
  env_vars.each do |k, v|
    puts "  #{k}=#{v}"
  end
end

# Apply env overrides
config_with_env = Movie::ActorSystemConfig.default.with_env_overrides

puts "\nConfig after env overrides:"
puts "  name: '#{config_with_env.get_string("name")}'"
puts "  remoting.port: #{config_with_env.get_int("remoting.port")}"
puts

# --- Example 5: Layered Config ---
puts "-" * 60
puts "Example 5: Layered Configuration"
puts "-" * 60

puts "Configuration layers (highest to lowest priority):"
puts "  1. Environment variables (MOVIE_*)"
puts "  2. Config file (YAML/JSON)"
puts "  3. Compiled defaults"
puts

# Simulate layered config
file_config = Movie::Config.from_yaml(<<-YAML)
  name: file-system
  remoting:
    port: 8000
YAML

layered = file_config
  .with_fallback(Movie::ActorSystemConfig.default)  # Defaults for missing values
  .with_env_overrides                                # Env vars override all

puts "Layered config result:"
puts "  name:          #{layered.get_string("name")} (from file or env)"
puts "  remoting.host: #{layered.get_string("remoting.host")} (from defaults)"
puts "  remoting.port: #{layered.get_int("remoting.port")} (from file or env)"
puts

# --- Cleanup ---
puts "-" * 60
puts "Cleanup"
puts "-" * 60

system2.remote.try(&.stop)

puts "[Done] Config example completed!"
puts
puts "Key features:"
puts "  1. Movie::ActorSystemConfig.default - compiled defaults"
puts "  2. Movie::Config.from_yaml/from_json - file loading"
puts "  3. config.with_env_overrides - environment overrides"
puts "  4. config.with_fallback - merge configs"
puts "  5. ActorSystem.new(behavior, config) - config-based creation"
puts "  6. Auto-enable remoting when remoting.enabled=true"
