require "log"

module JsonRpc
  abstract class Transport
    abstract def start(&on_message : String ->)
    abstract def send(message : String)
    abstract def close
  end

  class StdioTransport < Transport
    def initialize(
      @command : String,
      @args : Array(String) = [] of String,
      @env : Hash(String, String) = {} of String => String,
      @cwd : String? = nil
    )
      @write_channel = Channel(String).new(64)
      @process = Process.new(
        @command,
        @args,
        env: @env,
        chdir: @cwd,
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe
      )
    end

    def start(&on_message : String ->)
      stdout = @process.output
      stderr = @process.error

      spawn do
        while line = stdout.gets
          line = line.strip
          next if line.empty?
          on_message.call(line)
        end
      end

      spawn do
        while line = stderr.gets
          Log.for("jsonrpc").warn { "(stderr) #{line.strip}" }
        end
      end

      spawn do
        stdin = @process.input
        while message = @write_channel.receive?
          stdin.puts(message)
          stdin.flush
        end
      end
    end

    def send(message : String)
      @write_channel.send(message)
    end

    def close
      @write_channel.close
      @process.terminate
    end
  end
end
