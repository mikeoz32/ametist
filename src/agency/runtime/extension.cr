require "../../movie"
require "../agents/manager"
require "../llm/client"
require "./promise_receiver"
require "../mcp/client"
require "../mcp/adapter"
require "../skills/filesystem_source"
require "../skills/registry"
require "./system_message"

module Agency
  # Extension that wires Agency runtime actors and shared infrastructure.
  class AgencyExtension < Movie::Extension
    getter system : Movie::ActorSystem(SystemMessage)
    getter manager : AgentManager
    getter client : LLMClient
    getter default_model : String
    getter skill_registry : Movie::ActorRef(SkillRegistryMessage)

    def initialize(
      @system : Movie::ActorSystem(SystemMessage),
      @client : LLMClient,
      @default_model : String,
      skill_source : SkillSource = NullSkillSource.new
    )
      @skill_registry = @system.spawn(
        SkillRegistry.behavior(skill_source),
        Movie::RestartStrategy::RESTART,
        Movie::SupervisionConfig.default,
        "skill-registry"
      )
      @manager = AgentManager.spawn(@system, @client, @default_model, @skill_registry)
      rescan_skills
    end

    def stop
      @manager.stop
      @skill_registry.send_system(Movie::STOP)
    end

    def register_tool(spec : ToolSpec, ref : Movie::ActorRef(ToolCall))
      @manager.register_tool(spec, ref)
    end

    def register_tool(spec : ToolSpec, behavior : Movie::AbstractBehavior(ToolCall), name : String? = nil)
      @manager.register_tool(spec, behavior, name)
    end

    def register_exec_tool(spec : ToolSpec, handler : ExecTool)
      @manager.register_exec_tool(spec, handler)
    end

    def unregister_tool(name : String)
      @manager.unregister_tool(name)
    end

    def register_toolset(id : String, prefix : String, tools : Array(ToolSpec), ref : Movie::ActorRef(ToolSetMessage))
      @manager.register_toolset(id, prefix, tools, ref)
    end

    def register_toolset(id : String, prefix : String, tools : Array(ToolSpec), &factory : ToolSetFactory)
      @manager.register_toolset(id, prefix, tools, &factory)
    end

    def update_allowed_toolsets(agent_id : String, allowed_toolsets : Array(String)) : Movie::Future(Bool)
      @manager.update_allowed_toolsets(agent_id, allowed_toolsets)
    end

    def register_mcp_server(
      agent_id : String,
      command : String,
      args : Array(String) = [] of String,
      roots : Array(MCP::Root) = [] of MCP::Root,
      env : Hash(String, String) = {} of String => String,
      cwd : String? = nil,
      transport : JsonRpc::Transport? = nil,
      toolset_id : String? = nil,
      prefix : String? = nil
    ) : Movie::Future(Array(ToolSpec))
      promise = Movie::Promise(Array(ToolSpec)).new
      rpc_transport = transport || JsonRpc::StdioTransport.new(command, args, env, cwd)
      client = MCP::Client.new(rpc_transport, "agency", "0.1.0", roots)
      client.start
      id = toolset_id || command
      prefix_value = prefix || id

      executor = Movie::Execution.get(@system)
      init_future = executor.execute { client.initialize_connection }
      init_future.on_success do
        list_future = executor.execute { client.list_tools }
        list_future.on_success do |list|
          specs = list.tools.map { |tool| ToolSpec.new(tool.name, tool.description || "", tool.input_schema) }
          if transport
            adapter = @system.spawn(MCPAdapter.behavior(client), Movie::RestartStrategy::RESTART, Movie::SupervisionConfig.default)
            @manager.register_toolset(id, prefix_value, specs, adapter)
          else
            factory = ToolSetFactory.new do |_system|
              session_transport = JsonRpc::StdioTransport.new(command, args, env, cwd)
              session_client = MCP::Client.new(session_transport, "agency", "0.1.0", roots)
              MCPAdapter.behavior(session_client)
            end
            @manager.register_toolset(id, prefix_value, specs, &factory)
          end

          allowed_future = @manager.allowed_toolsets(agent_id)
          allowed_future.on_success do |allowed|
            merged = (allowed + [id]).uniq
            @manager.update_allowed_toolsets(agent_id, merged).on_success do
              promise.try_success(specs)
            end
          end
          allowed_future.on_failure { |ex| promise.try_failure(ex) }
        end
        list_future.on_failure { |ex| promise.try_failure(ex) }
      end
      init_future.on_failure { |ex| promise.try_failure(ex) }
      promise.future
    end

    def run(
      prompt : String,
      session_id : String = "default",
      model : String? = nil,
      agent_id : String = "default"
    ) : Movie::Future(String)
      @manager.run(prompt, session_id, model || @default_model, agent_id)
    end

    def rescan_skills
      @skill_registry << ReloadSkills.new
    end

    def rescan_skills_async : Movie::Future(Bool)
      promise = Movie::Promise(Bool).new
      receiver = @system.spawn(PromiseReceiver(Bool).new(promise))
      @skill_registry << ReloadSkills.new(receiver)
      promise.future
    end

    def get_skill(id : String) : Movie::Future(Skill?)
      promise = Movie::Promise(Skill?).new
      receiver = @system.spawn(PromiseReceiver(Skill?).new(promise))
      @skill_registry << GetSkill.new(id, receiver)
      promise.future
    end

    def list_skills : Movie::Future(Array(Skill))
      promise = Movie::Promise(Array(Skill)).new
      receiver = @system.spawn(PromiseReceiver(Array(Skill)).new(promise))
      @skill_registry << GetAllSkills.new(receiver)
      promise.future
    end
  end

  # Akka-style extension id for lazy Agency runtime wiring.
  class Extension < Movie::ExtensionId(AgencyExtension)
    def create(system : Movie::AbstractActorSystem) : AgencyExtension
      actor_system = system.as?(Movie::ActorSystem(SystemMessage))
      raise "Agency runtime requires ActorSystem" unless actor_system

      base_url = resolve_base_url(actor_system)
      api_key = resolve_api_key(actor_system, base_url)
      model = resolve_model(actor_system)
      client = LLMClient.new(api_key, base_url)
      skill_source = resolve_skill_source(actor_system)
      AgencyExtension.new(actor_system, client, model, skill_source)
    end

    private def resolve_api_key(system : Movie::AbstractActorSystem, base_url : String) : String
      key = ""
      unless system.config.empty?
        key = system.config.get_string("agency.llm.api_key", "")
      end
      if key.empty?
        key = ENV["OPENAI_API_KEY"]? || ""
      end
      if key.empty? && base_url.includes?("api.openai.com")
        raise "Missing OpenAI API key for Agency runtime"
      end
      key
    end

    private def resolve_base_url(system : Movie::AbstractActorSystem) : String
      url = ""
      unless system.config.empty?
        url = system.config.get_string("agency.llm.base_url", "")
      end
      if url.empty?
        url = ENV["OPENAI_BASE_URL"]? || ENV["OPENAI_API_BASE"]? || ""
      end
      url.empty? ? "https://api.openai.com" : url
    end

    private def resolve_model(system : Movie::AbstractActorSystem) : String
      return "gpt-3.5-turbo" if system.config.empty?
      model = system.config.get_string("agency.llm.model", "")
      model.empty? ? "gpt-3.5-turbo" : model
    end

    private def resolve_skill_source(system : Movie::ActorSystem(SystemMessage)) : SkillSource
      config = system.config
      paths = if config.empty?
                [] of String
              else
                config.get_string_array("agency.skills.paths", [] of String)
              end
      roots = paths.empty? ? FilesystemSkillSource.default_roots : paths
      FilesystemSkillSource.new(roots)
    end
  end

  # Convenience entry point: Agency.get(system)
  def self.get(system : Movie::ActorSystem(SystemMessage)) : AgencyExtension
    Extension.get(system)
  end
end
