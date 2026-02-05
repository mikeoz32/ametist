require "uuid"
require "../../movie"
require "../runtime/system_message"
require "./interface_extension"

module Agency
  # System root behavior that proxies prompts to the TUI adapter.
  class TuiRoot < Movie::AbstractBehavior(TuiRootMessage)

    def self.behavior : Movie::AbstractBehavior(TuiRootMessage)
      Movie::Behaviors(TuiRootMessage).setup do |ctx|
        tui = Agency::TuiInterface.get(ctx.system.as(Movie::ActorSystem(SystemMessage)))
        session_id = UUID.random.to_s
        TuiRoot.new(tui.agency, tui.adapter, session_id, tui.default_model, "default")
      end
    end

    def initialize(
      @agency : AgencyExtension,
      @adapter : Movie::ActorRef(TuiMessage),
      @session_id : String,
      @model : String,
      @agent_id : String
    )
    end

    def receive(message, ctx)
      case message
      when TuiInput
        send_prompt(message.prompt, ctx)
      when TuiHelp
        reply(ctx, "commands: /help /session /model /agent /skills /skills reload /exit /quit /q")
      when TuiSetSession
        @session_id = message.session_id
        reply(ctx, "session=#{@session_id}")
      when TuiSetModel
        @model = message.model
        reply(ctx, "model=#{@model}")
      when TuiSetAgent
        @agent_id = message.agent_id
        reply(ctx, "agent=#{@agent_id}")
      when TuiReloadSkills
        rescan_skills(ctx)
      when TuiListSkills
        list_skills(ctx)
      end

      Movie::Behaviors(TuiRootMessage).same
    end

    private def send_prompt(prompt : String, ctx)
      sender = ctx.sender
      future = ctx.ask(@adapter, TuiRun.new(prompt, @session_id, @model, @agent_id), String)
      future.on_success { |value| Movie::Ask.reply_if_asked(sender, value) }
      future.on_failure { |ex| Movie::Ask.fail_if_asked(sender, ex, String) }
    end

    private def reply(ctx, text : String)
      sender = ctx.sender
      return unless sender
      return if sender == ctx.ref
      Movie::Ask.reply_if_asked(sender, text)
    end

    private def rescan_skills(ctx)
      sender = ctx.sender
      future = @agency.rescan_skills_async
      future.on_success { Movie::Ask.reply_if_asked(sender, "skills reloaded") }
      future.on_failure { |ex| Movie::Ask.fail_if_asked(sender, ex, String) }
    end

    private def list_skills(ctx)
      sender = ctx.sender
      future = @agency.list_skills
      future.on_success do |skills|
        ids = skills.map(&.id).sort
        text = ids.empty? ? "skills: (none)" : "skills: #{ids.join(", ")}"
        Movie::Ask.reply_if_asked(sender, text)
      end
      future.on_failure { |ex| Movie::Ask.fail_if_asked(sender, ex, String) }
    end
  end
end
