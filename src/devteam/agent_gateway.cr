require "../movie"
require "../agency/runtime/extension"

module DevTeam
  abstract class AgentGateway
    abstract def run(role : String, prompt : String, session_id : String, org_id : String, project_id : String) : Movie::Future(String)
  end

  class AgencyGateway < AgentGateway
    def initialize(@agency : Agency::AgencyExtension)
    end

    def run(role : String, prompt : String, session_id : String, org_id : String, project_id : String) : Movie::Future(String)
      agent_id = role
      @agency.run(prompt, session_id, agent_id: agent_id)
    end
  end
end
