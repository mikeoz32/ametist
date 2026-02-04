require "../movie"
require "./protocol"
require "./llm_client"
require "./llm_gateway"
require "./agent_messages"
require "./agent_actor"
require "./agent_profile"
require "./promise_receiver"
require "./skill_registry"
require "./system_message"

module Agency
  DEFAULT_INFRA_SUPERVISION = Movie::SupervisionConfig.new(
    strategy: Movie::SupervisionStrategy::RESTART,
    scope: Movie::SupervisionScope::ONE_FOR_ONE,
    max_restarts: 5,
    within: 5.seconds,
    backoff_min: 50.milliseconds,
    backoff_max: 2.seconds,
    backoff_factor: 2.0,
    jitter: 0.1,
  )

  DEFAULT_SESSION_SUPERVISION = Movie::SupervisionConfig.new(
    strategy: Movie::SupervisionStrategy::RESTART,
    scope: Movie::SupervisionScope::ONE_FOR_ONE,
    max_restarts: 3,
    within: 2.seconds,
    backoff_min: 20.milliseconds,
    backoff_max: 1.second,
    backoff_factor: 2.0,
    jitter: 0.1,
  )

  DEFAULT_TOOL_SUPERVISION = DEFAULT_INFRA_SUPERVISION

  # Messages handled by the manager actor.
  struct RegisterTool
    getter spec : ToolSpec
    getter ref : Movie::ActorRef(ToolCall)

    def initialize(@spec : ToolSpec, @ref : Movie::ActorRef(ToolCall))
    end
  end

  struct RegisterToolBehavior
    getter spec : ToolSpec
    getter behavior : Movie::AbstractBehavior(ToolCall)
    getter name : String?

    def initialize(@spec : ToolSpec, @behavior : Movie::AbstractBehavior(ToolCall), @name : String? = nil)
    end
  end

  struct RegisterExecTool
    getter spec : ToolSpec
    getter handler : ExecTool

    def initialize(@spec : ToolSpec, @handler : ExecTool)
    end
  end

  struct UnregisterTool
    getter name : String

    def initialize(@name : String)
    end
  end

  struct UpdateAgentAllowlist
    getter agent_id : String
    getter allowed_tools : Array(String)
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@agent_id : String, @allowed_tools : Array(String), @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  alias ManagerMessage = RegisterTool | RegisterToolBehavior | RegisterExecTool | UnregisterTool | RunPrompt | UpdateAgentAllowlist

  # Actor that owns sessions and tool registry.
  class AgentManagerActor < Movie::AbstractBehavior(ManagerMessage)
    MAX_HISTORY = 50
    MAX_STEPS = 8
    @llm_gateway : Movie::ActorRef(LLMRequest)
    @agents : Hash(String, Movie::ActorRef(AgentMessage))
    @tool_specs : Array(ToolSpec)
    @tool_specs_by_name : Hash(String, ToolSpec)
    @actor_tools : Hash(String, Movie::ActorRef(ToolCall))
    @exec_tools : Hash(String, ExecTool)
    @default_model : String
    @agent_supervision : Movie::SupervisionConfig
    @session_supervision : Movie::SupervisionConfig

    def self.behavior(
      client : LLMClient,
      default_model : String = "gpt-3.5-turbo",
      supervision : Movie::SupervisionConfig = DEFAULT_INFRA_SUPERVISION,
      session_supervision : Movie::SupervisionConfig = DEFAULT_SESSION_SUPERVISION
    ) : Movie::AbstractBehavior(ManagerMessage)
      Movie::Behaviors(ManagerMessage).setup do |ctx|
        llm_gateway = ctx.spawn(LLMGateway.behavior(client), Movie::RestartStrategy::RESTART, supervision, "llm-gateway")
        AgentManagerActor.new(llm_gateway, default_model, supervision, session_supervision)
      end
    end

    def initialize(
      @llm_gateway : Movie::ActorRef(LLMRequest),
      @default_model : String,
      @agent_supervision : Movie::SupervisionConfig,
      @session_supervision : Movie::SupervisionConfig
    )
      @agents = {} of String => Movie::ActorRef(AgentMessage)
      @tool_specs = [] of ToolSpec
      @tool_specs_by_name = {} of String => ToolSpec
      @actor_tools = {} of String => Movie::ActorRef(ToolCall)
      @exec_tools = {} of String => ExecTool
    end

    def receive(message, ctx)
      case message
      when RegisterTool
        upsert_tool_spec(message.spec)
        @actor_tools[message.spec.name] = message.ref
        broadcast_tool_register(ToolSetRegisterActor.new(message.spec, message.ref))
      when RegisterToolBehavior
        upsert_tool_spec(message.spec)
        tool_ref = ctx.spawn(
          message.behavior,
          Movie::RestartStrategy::RESTART,
          DEFAULT_TOOL_SUPERVISION,
          message.name
        )
        @actor_tools[message.spec.name] = tool_ref
        broadcast_tool_register(ToolSetRegisterActor.new(message.spec, tool_ref))
      when RegisterExecTool
        upsert_tool_spec(message.spec)
        @exec_tools[message.spec.name] = message.handler
        broadcast_tool_register(ToolSetRegisterExec.new(message.spec, message.handler))
      when UnregisterTool
        @tool_specs.reject! { |s| s.name == message.name }
        @tool_specs_by_name.delete(message.name)
        @actor_tools.delete(message.name)
        @exec_tools.delete(message.name)
        broadcast_tool_register(ToolSetUnregister.new(message.name))
      when RunPrompt
        agent = ensure_agent(message.agent_id, ctx)
        agent << message
      when UpdateAgentAllowlist
        agent = ensure_agent(message.agent_id, ctx)
        agent << UpdateAllowedTools.new(message.allowed_tools)
        seed_agent_tools(agent)
        reply_bool(message.reply_to, ctx, true)
      end
      Movie::Behaviors(ManagerMessage).same
    end

    private def ensure_agent(id : String, ctx) : Movie::ActorRef(AgentMessage)
      if existing = @agents[id]?
        return existing
      end
      cfg = ctx.system.config
      default_policy = cfg.get_string("agency.agents.default.memory_policy", "")
      policy_name = cfg.get_string("agency.agents.#{id}.memory_policy", default_policy)
      policy_name = nil if policy_name.empty?
      default_allowed = cfg.get_string_array("agency.agents.default.allowed_tools", [] of String)
      allowed_tools = cfg.get_string_array("agency.agents.#{id}.allowed_tools", default_allowed)
      profile = AgentProfile.new(id, @default_model, MAX_STEPS, MAX_HISTORY, policy_name, allowed_tools)
      agent = ctx.spawn(
        AgentActor.behavior(
          profile,
          @llm_gateway,
          @tool_specs.dup,
          @agent_supervision,
          @session_supervision
        ),
        Movie::RestartStrategy::RESTART,
        @agent_supervision
      )
      @agents[id] = agent
      seed_agent_tools(agent)
      agent
    end

    private def upsert_tool_spec(spec : ToolSpec)
      @tool_specs.reject! { |s| s.name == spec.name }
      @tool_specs << spec
      @tool_specs_by_name[spec.name] = spec
    end

    private def broadcast_tool_register(message : ToolSetMessage)
      @agents.each_value do |agent|
        agent << message
      end
    end

    private def seed_agent_tools(agent : Movie::ActorRef(AgentMessage))
      @exec_tools.each do |name, handler|
        if spec = @tool_specs_by_name[name]?
          agent << ToolSetRegisterExec.new(spec, handler)
        end
      end
      @actor_tools.each do |name, ref|
        if spec = @tool_specs_by_name[name]?
          agent << ToolSetRegisterActor.new(spec, ref)
        end
      end
    end

    private def reply_bool(reply_to, ctx, value : Bool)
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(ctx.sender, value)
      end
    end

    def stop
      @agents.each_value(&.send_system(Movie::STOP))
      @agents.clear
      @llm_gateway.send_system(Movie::STOP)
    end
  end

  # Facade used by callers; delegates to the manager actor via messages.
  class AgentManager
    getter ref : Movie::ActorRef(ManagerMessage)

    def self.spawn(
      system : Movie::ActorSystem(SystemMessage),
      client : LLMClient,
      default_model : String = "gpt-3.5-turbo",
      skill_registry : Movie::ActorRef(SkillRegistryMessage)? = nil,
      supervision : Movie::SupervisionConfig = DEFAULT_INFRA_SUPERVISION,
      session_supervision : Movie::SupervisionConfig = DEFAULT_SESSION_SUPERVISION
    ) : AgentManager
      ref = system.spawn(AgentManagerActor.behavior(client, default_model, supervision, session_supervision))
      new(system, ref, skill_registry)
    end

    def initialize(
      @system : Movie::ActorSystem(SystemMessage),
      @ref : Movie::ActorRef(ManagerMessage),
      @skill_registry : Movie::ActorRef(SkillRegistryMessage)? = nil
    )
    end

    def register_tool(spec : ToolSpec, ref : Movie::ActorRef(ToolCall))
      @ref << RegisterTool.new(spec, ref)
    end

    def register_tool(spec : ToolSpec, behavior : Movie::AbstractBehavior(ToolCall), name : String? = nil)
      @ref << RegisterToolBehavior.new(spec, behavior, name)
    end

    def register_exec_tool(spec : ToolSpec, handler : ExecTool)
      @ref << RegisterExecTool.new(spec, handler)
    end

    def unregister_tool(name : String)
      @ref << UnregisterTool.new(name)
    end

    def update_allowed_tools(agent_id : String, allowed_tools : Array(String)) : Movie::Future(Bool)
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(PromiseReceiver(Bool).new(promise))
      @ref << UpdateAgentAllowlist.new(agent_id, allowed_tools, receiver)
      promise.future
    end

    def run(
      prompt : String,
      session_id : String = "default",
      model : String = "gpt-3.5-turbo",
      agent_id : String = "default"
    ) : Movie::Future(String)
      promise = Movie::Promise(String).new
      receiver = @system.spawn(StringResultReceiver.new(promise))
      @ref << RunPrompt.new(prompt, session_id, model, receiver.as(Movie::ActorRef(String)), agent_id)
      promise.future
    end

    def rescan_skills
      return unless @skill_registry
      @skill_registry << ReloadSkills.new
    end

    def rescan_skills_async : Movie::Future(Bool)
      registry = @skill_registry
      raise "Skill registry not configured" unless registry
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(PromiseReceiver(Bool).new(promise))
      registry << ReloadSkills.new(receiver)
      promise.future
    end

    def stop
      @ref.send_system(Movie::STOP)
    end
  end

  # Receiver actor that fulfills a promise when a String result arrives.
  class StringResultReceiver < Movie::AbstractBehavior(String)
    def initialize(@promise : Movie::Promise(String))
    end

    def receive(message, ctx)
      @promise.try_success(message)
      Movie::Behaviors(String).same
    end
  end
end
