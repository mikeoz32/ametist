require "../movie/persistence"

module DevTeam
  struct OrgState
    include JSON::Serializable

    getter org_id : String
    getter name : String
    getter projects : Array(String)

    def initialize(@org_id : String = "", @name : String = "", @projects : Array(String) = [] of String)
    end

    def with_name(name : String) : OrgState
      OrgState.new(@org_id, name, @projects)
    end

    def with_id(org_id : String) : OrgState
      OrgState.new(org_id, @name, @projects)
    end

    def with_projects(projects : Array(String)) : OrgState
      OrgState.new(@org_id, @name, projects)
    end
  end

  struct CreateOrg
    getter org_id : String
    getter name : String

    def initialize(@org_id : String, @name : String)
    end
  end

  struct RegisterProject
    getter project_id : String

    def initialize(@project_id : String)
    end
  end

  struct GetOrgState
    getter org_id : String

    def initialize(@org_id : String)
    end
  end

  alias OrgCommand = CreateOrg | RegisterProject | GetOrgState

  class OrgEntity < Movie::DurableStateBehavior(OrgCommand, OrgState)
    def empty_state : OrgState
      OrgState.new
    end

    def handle_command(state : OrgState, command : OrgCommand, ctx : Movie::ActorContext(OrgCommand)) : OrgState?
      case command
      when CreateOrg
        next_state = state.with_id(command.org_id).with_name(command.name)
        Movie::Ask.reply_if_asked(ctx.sender, next_state)
        next_state
      when RegisterProject
        projects = (state.projects + [command.project_id]).uniq
        next_state = state.with_projects(projects)
        Movie::Ask.reply_if_asked(ctx.sender, next_state)
        next_state
      when GetOrgState
        Movie::Ask.reply_if_asked(ctx.sender, state)
        nil
      end
    end
  end
end
