require "option_parser"
require "json"
require "uuid"
require "../agency"

module AgencyCLI
  def self.print_help
    puts "Commands:"
    puts "  /help                 Show commands"
    puts "  /exit | /quit | /q     Exit"
    puts "  /session <id>          Switch session id"
    puts "  /model <name>          Switch model"
    puts "  /skills                List skills"
    puts "  /skills reload         Reload skills"
  end

  def self.run
    Agency::EnvLoader.load

    api_key = ENV["OPENAI_API_KEY"]?
    base_url = ENV["OPENAI_BASE_URL"]? || ENV["OPENAI_API_BASE"]?
    model = "gpt-4.1-nano"
    session_id = UUID.random.to_s
    agent_id = "default"
    interactive = true

    OptionParser.parse do |parser|
      parser.banner = "Usage: agency [options] [prompt]"
      parser.on("--api-key=KEY", "OpenAI API key (default: OPENAI_API_KEY)") { |v| api_key = v }
      parser.on("--base-url=URL", "OpenAI-compatible base URL (e.g. http://localhost:11434/v1)") { |v| base_url = v }
      parser.on("--model=MODEL", "Model name") { |v| model = v }
      parser.on("--session=ID", "Session id (keeps history)") { |v| session_id = v }
      parser.on("--once", "Run a single prompt from args or stdin") { interactive = false }
      parser.on("-h", "--help", "Show help") do
        puts parser
        exit
      end
    end

    api_key_value = api_key.to_s
    base_url_value = base_url.to_s
    if base_url_value.empty?
      # base_url_value = "http://localhost:12434/engines/v1"
      base_url_value = "https://models.github.ai/inference"
    end
    if api_key_value.empty? && base_url_value.includes?("api.openai.com")
      STDERR.puts "Missing OpenAI API key for OpenAI base URL."
      exit 1
    end

    builder = Movie::Config.builder
      .set("agency.llm.api_key", api_key_value)
      .set("agency.llm.model", model)
    builder = builder.set("agency.llm.base_url", base_url_value) unless base_url_value.empty?
    config = builder.build

    system = Movie::ActorSystem(Agency::SystemMessage).new(Agency::TuiRoot.behavior, config)
    tui = nil.as(Agency::TuiInterfaceExtension?)
    100.times do
      tui = system.extension(Agency::TuiInterfaceExtension)
      break if tui
      sleep 10.milliseconds
    end
    raise "TUI interface not initialized" unless tui
    runtime_ext = tui.agency

    system << Agency::TuiSetSession.new(session_id)
    system << Agency::TuiSetModel.new(model)
    system << Agency::TuiSetAgent.new(agent_id)

    prompt = ARGV.join(" ").strip
    if !interactive
      if prompt.empty?
        input = STDIN.gets
        if input
          prompt = String.build do |io|
            io << input
            while more = STDIN.gets
              io << more
            end
          end
        end
      end
      prompt = prompt.strip
      if prompt.empty?
        STDERR.puts "No prompt provided."
        exit 1
      end
      begin
        response = system.ask(Agency::TuiInput.new(prompt), String).await
        puts response
      rescue ex
        STDERR.puts "Error: #{ex.message}"
        exit 1
      end
      return
    end

    puts "Agency CLI"
    puts "model=#{model} session=#{session_id}"
    puts "Type /help for commands."

    while line = STDIN.gets
      line = line.strip
      next if line.empty?

      if line.starts_with?("/")
        parts = line.split(' ', 2)
        cmd = parts[0]
        arg = parts.size > 1 ? parts[1].strip : ""

        case cmd
        when "/exit", "/quit", "/q"
          break
        when "/help"
          begin
            response = system.ask(Agency::TuiHelp.new, String).await
            puts response
          rescue ex
            STDERR.puts "Error: #{ex.message}"
          end
        when "/session"
          begin
            if arg.empty?
              puts "current session=#{session_id}"
            else
              response = system.ask(Agency::TuiSetSession.new(arg), String).await
              puts response
              session_id = arg
            end
          rescue ex
            STDERR.puts "Error: #{ex.message}"
          end
        when "/model"
          begin
            if arg.empty?
              puts "current model=#{model}"
            else
              response = system.ask(Agency::TuiSetModel.new(arg), String).await
              puts response
              model = arg
            end
          rescue ex
            STDERR.puts "Error: #{ex.message}"
          end
        when "/agent"
          begin
            if arg.empty?
              puts "current agent=#{agent_id}"
            else
              response = system.ask(Agency::TuiSetAgent.new(arg), String).await
              puts response
              agent_id = arg
            end
          rescue ex
            STDERR.puts "Error: #{ex.message}"
          end
        when "/skills"
          begin
            if arg.empty? || arg == "list"
              response = system.ask(Agency::TuiListSkills.new, String).await
              puts response
            elsif arg == "reload"
              response = system.ask(Agency::TuiReloadSkills.new, String).await
              puts response
            else
              puts "Usage: /skills [list|reload]"
            end
          rescue ex
            STDERR.puts "Error: #{ex.message}"
          end
        else
          puts "Unknown command. Type /help"
        end
        next
      end

      begin
        response = system.ask(Agency::TuiInput.new(line), String).await
        puts response
      rescue ex
        STDERR.puts "Error: #{ex.message}"
      end
    end
  end
end

AgencyCLI.run
