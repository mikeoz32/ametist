require "../../movie"
require "../runtime/protocol"
require "../llm/client"
require "../llm/gateway"
require "./messages"
require "./actor"
require "./profile"
require "../runtime/promise_receiver"
require "../skills/registry"
require "../runtime/system_message"
require "../tools/tool_set"
require "../tools/toolset_definition"

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
  DEFAULT_TOOLSET_ID = "local"
  DEFAULT_TOOLSET_PREFIX = "local"

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

  struct RegisterToolSet
    getter definition : ToolSetDefinition

    def initialize(@definition : ToolSetDefinition)
    end
  end

  struct UpdateAgentToolsetAllowlist
    getter agent_id : String
    getter allowed_toolsets : Array(String)
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@agent_id : String, @allowed_toolsets : Array(String), @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct GetAllowedToolSets
    getter agent_id : String
    getter reply_to : Movie::ActorRef(Array(String))

    def initialize(@agent_id : String, @reply_to : Movie::ActorRef(Array(String)))
    end
  end

  alias ManagerMessage = RegisterTool | RegisterToolBehavior | RegisterExecTool | UnregisterTool | RegisterToolSet | RunPrompt | UpdateAgentToolsetAllowlist | GetAllowedToolSets

  # Actor that owns sessions and tool registry.
  class AgentManagerActor < Movie::AbstractBehavior(ManagerMessage)
    MAX_HISTORY = 50
    MAX_STEPS = 8
    @llm_gateway : Movie::ActorRef(LLMRequest)
    @agents : Hash(String, Movie::ActorRef(AgentMessage))
    @toolset_defs : Hash(String, ToolSetDefinition)
    @default_tool_specs : Array(ToolSpec)
    @default_tool_specs_by_name : Hash(String, ToolSpec)
    @default_actor_tools : Hash(String, Movie::ActorRef(ToolCall))
    @default_exec_tools : Hash(String, ExecTool)
    @default_model : String
    @agent_supervision : Movie::SupervisionConfig
    @session_supervision : Movie::SupervisionConfig
    @allowed_toolsets_by_agent : Hash(String, Array(String))

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
      @toolset_defs = {} of String => ToolSetDefinition
      @default_tool_specs = [] of ToolSpec
      @default_tool_specs_by_name = {} of String => ToolSpec
      @default_actor_tools = {} of String => Movie::ActorRef(ToolCall)
      @default_exec_tools = {} of String => ExecTool
      @allowed_toolsets_by_agent = {} of String => Array(String)
    end

    def receive(message, ctx)
      case message
      when RegisterTool
        upsert_default_tool_spec(message.spec)
        @default_actor_tools[message.spec.name] = message.ref
        refresh_default_toolset
      when RegisterToolBehavior
        upsert_default_tool_spec(message.spec)
        tool_ref = ctx.spawn(
          message.behavior,
          Movie::RestartStrategy::RESTART,
          DEFAULT_TOOL_SUPERVISION,
          message.name
        )
        @default_actor_tools[message.spec.name] = tool_ref
        refresh_default_toolset
      when RegisterExecTool
        upsert_default_tool_spec(message.spec)
        @default_exec_tools[message.spec.name] = message.handler
        refresh_default_toolset
      when UnregisterTool
        @default_tool_specs.reject! { |s| s.name == message.name }
        @default_tool_specs_by_name.delete(message.name)
        @default_actor_tools.delete(message.name)
        @default_exec_tools.delete(message.name)
        refresh_default_toolset
      when RegisterToolSet
        @toolset_defs[message.definition.id] = message.definition
        broadcast_toolset_definition(message.definition)
      when RunPrompt
        agent = ensure_agent(message.agent_id, ctx)
        agent << message
      when UpdateAgentToolsetAllowlist
        agent = ensure_agent(message.agent_id, ctx)
        agent << UpdateAllowedToolSets.new(message.allowed_toolsets)
        @allowed_toolsets_by_agent[message.agent_id] = message.allowed_toolsets
        reply_bool(message.reply_to, ctx, true)
      when GetAllowedToolSets
        allowed = allowed_toolsets_for(message.agent_id, ctx)
        message.reply_to << allowed
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
      allowed_toolsets = allowed_toolsets_for(id, ctx)
      profile = AgentProfile.new(id, @default_model, MAX_STEPS, MAX_HISTORY, policy_name, allowed_toolsets)
      agent = ctx.spawn(
        AgentActor.behavior(
          profile,
          @llm_gateway,
          @toolset_defs.values,
          @agent_supervision,
          @session_supervision
        ),
        Movie::RestartStrategy::RESTART,
        @agent_supervision
      )
      @agents[id] = agent
      broadcast_toolsets_to(agent)
      agent
    end

    private def upsert_default_tool_spec(spec : ToolSpec)
      @default_tool_specs.reject! { |s| s.name == spec.name }
      @default_tool_specs << spec
      @default_tool_specs_by_name[spec.name] = spec
    end

    private def broadcast_toolset_definition(definition : ToolSetDefinition)
      @agents.each_value do |agent|
        agent << RegisterToolSetDefinition.new(definition)
      end
    end

    private def broadcast_toolsets_to(agent : Movie::ActorRef(AgentMessage))
      @toolset_defs.each_value do |definition|
        agent << RegisterToolSetDefinition.new(definition)
      end
    end

    private def allowed_toolsets_for(agent_id : String, ctx) : Array(String)
      if existing = @allowed_toolsets_by_agent[agent_id]?
        return existing
      end
      cfg = ctx.system.config
      default_allowed = cfg.get_string_array("agency.agents.default.allowed_toolsets", [] of String)
      allowed = cfg.get_string_array("agency.agents.#{agent_id}.allowed_toolsets", default_allowed)
      @allowed_toolsets_by_agent[agent_id] = allowed
      allowed
    end

    private def refresh_default_toolset
      definition = build_default_toolset_definition
      @toolset_defs[definition.id] = definition
      broadcast_toolset_definition(definition)
    end

    private def build_default_toolset_definition : ToolSetDefinition
      tools_snapshot = @default_tool_specs.dup
      exec_snapshot = @default_exec_tools.dup
      actor_snapshot = @default_actor_tools.dup
      specs_snapshot = @default_tool_specs_by_name.dup

      factory = ToolSetFactory.new do |system|
        executor = Movie::Execution.get(system)
        DefaultToolSet.new(executor, exec_snapshot.dup, actor_snapshot.dup, specs_snapshot.dup)
      end

      ToolSetDefinition.new(DEFAULT_TOOLSET_ID, DEFAULT_TOOLSET_PREFIX, tools_snapshot, factory)
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

    def register_toolset(id : String, prefix : String, tools : Array(ToolSpec), ref : Movie::ActorRef(ToolSetMessage))
      definition = ToolSetDefinition.new(id, prefix, tools, ref)
      @ref << RegisterToolSet.new(definition)
    end

    def register_toolset(id : String, prefix : String, tools : Array(ToolSpec), &factory : ToolSetFactory)
      definition = ToolSetDefinition.new(id, prefix, tools, factory)
      @ref << RegisterToolSet.new(definition)
    end

    def update_allowed_toolsets(agent_id : String, allowed_toolsets : Array(String)) : Movie::Future(Bool)
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(PromiseReceiver(Bool).new(promise))
      @ref << UpdateAgentToolsetAllowlist.new(agent_id, allowed_toolsets, receiver)
      promise.future
    end

    def allowed_toolsets(agent_id : String) : Movie::Future(Array(String))
      promise = Movie::Promise(Array(String)).new
      receiver = @system.spawn(PromiseReceiver(Array(String)).new(promise))
      @ref << GetAllowedToolSets.new(agent_id, receiver)
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
