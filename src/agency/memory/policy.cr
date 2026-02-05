require "../../movie"

module Agency
  struct ScopePolicy
    getter max_history : Int32
    getter semantic_k : Int32
    getter graph_k : Int32

    def initialize(@max_history : Int32, @semantic_k : Int32, @graph_k : Int32)
    end
  end

  struct MemoryPolicy
    getter summary_token_threshold : Int32
    getter session : ScopePolicy
    getter project : ScopePolicy
    getter user : ScopePolicy

    def initialize(
      @summary_token_threshold : Int32,
      @session : ScopePolicy,
      @project : ScopePolicy,
      @user : ScopePolicy
    )
    end

    def self.from_config(config : Movie::Config) : MemoryPolicy
      build_base_policy(config)
    end

    def self.from_config(config : Movie::Config, name : String?) : MemoryPolicy
      base = build_base_policy(config)
      return base if name.nil? || name.empty?

      prefix = "agency.memory.policies.#{name}"
      summary_threshold = override_int(config, "#{prefix}.summary_token_threshold", base.summary_token_threshold)

      session = override_scope(config, "#{prefix}", base.session)
      project = override_scope(config, "#{prefix}.project", base.project)
      user = override_scope(config, "#{prefix}.user", base.user)

      MemoryPolicy.new(summary_threshold, session, project, user)
    end

    private def self.build_base_policy(config : Movie::Config) : MemoryPolicy
      summary_threshold = config.get_int("agency.memory.summary_token_threshold", 8000)

      session_max_history = config.get_int("agency.memory.max_history", 50)
      session_semantic_k = config.get_int("agency.memory.semantic_k", 5)
      session_graph_k = config.get_int("agency.memory.graph_k", 10)

      project_max_history = config.get_int("agency.memory.project.max_history", session_max_history)
      project_semantic_k = config.get_int("agency.memory.project.semantic_k", 3)
      project_graph_k = config.get_int("agency.memory.project.graph_k", 5)

      user_max_history = config.get_int("agency.memory.user.max_history", session_max_history)
      user_semantic_k = config.get_int("agency.memory.user.semantic_k", 2)
      user_graph_k = config.get_int("agency.memory.user.graph_k", 3)

      MemoryPolicy.new(
        summary_threshold,
        ScopePolicy.new(session_max_history, session_semantic_k, session_graph_k),
        ScopePolicy.new(project_max_history, project_semantic_k, project_graph_k),
        ScopePolicy.new(user_max_history, user_semantic_k, user_graph_k)
      )
    end

    private def self.override_scope(config : Movie::Config, prefix : String, base : ScopePolicy) : ScopePolicy
      max_history = override_int(config, "#{prefix}.max_history", base.max_history)
      semantic_k = override_int(config, "#{prefix}.semantic_k", base.semantic_k)
      graph_k = override_int(config, "#{prefix}.graph_k", base.graph_k)
      ScopePolicy.new(max_history, semantic_k, graph_k)
    end

    private def self.override_int(config : Movie::Config, path : String, current : Int32) : Int32
      return current unless config.has_path?(path)
      config.get_int(path, current)
    end
  end
end
