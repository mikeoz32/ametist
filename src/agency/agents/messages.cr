require "../../movie"
require "../runtime/protocol"
require "../tools/toolset_definition"

module Agency
  alias ExecTool = Proc(ToolCall, String)

  struct ToolSetRegisterExec
    getter spec : ToolSpec
    getter handler : ExecTool

    def initialize(@spec : ToolSpec, @handler : ExecTool)
    end
  end

  struct ToolSetRegisterActor
    getter spec : ToolSpec
    getter ref : Movie::ActorRef(ToolCall)

    def initialize(@spec : ToolSpec, @ref : Movie::ActorRef(ToolCall))
    end
  end

  struct ToolSetUnregister
    getter name : String

    def initialize(@name : String)
    end
  end

  struct UpdateAllowedToolSets
    getter allowed_toolsets : Array(String)

    def initialize(@allowed_toolsets : Array(String))
    end
  end

  struct RegisterToolSetDefinition
    getter definition : ToolSetDefinition

    def initialize(@definition : ToolSetDefinition)
    end
  end


  alias ToolSetMessage = ToolCall | ToolSetRegisterExec | ToolSetRegisterActor | ToolSetUnregister

  struct StartSession
    getter session_id : String

    def initialize(@session_id : String)
    end
  end

  struct StopSession
    getter session_id : String

    def initialize(@session_id : String)
    end
  end

  struct GetAgentState
    getter reply_to : Movie::ActorRef(AgentState)

    def initialize(@reply_to : Movie::ActorRef(AgentState))
    end
  end

  struct AttachSkills
    getter skill_ids : Array(String)
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@skill_ids : Array(String), @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct DetachSkills
    getter skill_ids : Array(String)
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@skill_ids : Array(String), @reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct GetAttachedSkills
    getter reply_to : Movie::ActorRef(Array(String))?

    def initialize(@reply_to : Movie::ActorRef(Array(String))? = nil)
    end
  end

  struct AgentState
    getter agent_id : String
    getter sessions : Array(String)

    def initialize(@agent_id : String, @sessions : Array(String))
    end
  end

  # External request routed through AgentManager -> AgentActor.
  struct RunPrompt
    getter agent_id : String
    getter session_id : String
    getter prompt : String
    getter model : String
    getter reply_to : Movie::ActorRef(String)
    getter user_id : String?
    getter project_id : String?

    def initialize(@prompt : String,
                   @session_id : String,
                   @model : String,
                   @reply_to : Movie::ActorRef(String),
                   @agent_id : String = "default",
                   @user_id : String? = nil,
                   @project_id : String? = nil)
    end
  end

  # Session-level prompt (sent to AgentSession).
  struct SessionPrompt
    getter agent_id : String
    getter prompt : String
    getter model : String
    getter reply_to : Movie::ActorRef(String)
    getter user_id : String?
    getter project_id : String?

    def initialize(@agent_id : String,
                   @prompt : String,
                   @model : String,
                   @reply_to : Movie::ActorRef(String),
                   @user_id : String? = nil,
                   @project_id : String? = nil)
    end
  end

  struct RunCompleted
    getter content : String
    getter delta : Array(Message)

    def initialize(@content : String, @delta : Array(Message))
    end
  end

  struct RunFailed
    getter error : String
    getter delta : Array(Message)

    def initialize(@error : String, @delta : Array(Message))
    end
  end

  struct GetSessionState
    getter reply_to : Movie::ActorRef(SessionState)

    def initialize(@reply_to : Movie::ActorRef(SessionState))
    end
  end

  struct SessionState
    getter session_id : String
    getter history_size : Int32
    getter active_run : Bool

    def initialize(@session_id : String, @history_size : Int32, @active_run : Bool)
    end
  end

  struct HistoryLoaded
    getter events : Array(Message)

    def initialize(@events : Array(Message))
    end
  end

  alias AgentMessage = RunPrompt | StartSession | StopSession | GetAgentState | AttachSkills | DetachSkills | GetAttachedSkills | ToolSetRegisterExec | ToolSetRegisterActor | ToolSetUnregister | UpdateAllowedToolSets | RegisterToolSetDefinition
  alias SessionMessage = SessionPrompt | RunCompleted | RunFailed | GetSessionState | HistoryLoaded
end
