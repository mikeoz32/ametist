require "../movie"
require "./agent_manager"
require "./agent_messages"

module Agency
  struct TuiRun
    getter prompt : String
    getter session_id : String
    getter model : String
    getter agent_id : String

    def initialize(
      @prompt : String,
      @session_id : String,
      @model : String,
      @agent_id : String
    )
    end
  end

  alias TuiMessage = TuiRun

  # Minimal TUI adapter that maps prompts to AgentManager runs.
  class TuiAdapter < Movie::AbstractBehavior(TuiMessage)
    def self.behavior(
      manager : AgentManager,
      default_model : String = "gpt-3.5-turbo",
      default_agent_id : String = "default"
    ) : Movie::AbstractBehavior(TuiMessage)
      Movie::Behaviors(TuiMessage).setup do |_ctx|
        TuiAdapter.new(manager, default_model, default_agent_id)
      end
    end

    def initialize(
      @manager : AgentManager,
      @default_model : String,
      @default_agent_id : String
    )
    end

    def receive(message, ctx)
      case message
      when TuiRun
        model = message.model.empty? ? @default_model : message.model
        agent_id = message.agent_id.empty? ? @default_agent_id : message.agent_id
        sender = ctx.sender
        future = @manager.run(message.prompt, message.session_id, model, agent_id)
        future.on_success { |value| Movie::Ask.reply_if_asked(sender, value) }
        future.on_failure { |ex| Movie::Ask.fail_if_asked(sender, ex, String) }
      end
      Movie::Behaviors(TuiMessage).same
    end
  end
end
