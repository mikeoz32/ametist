require "json"

module DevTeam
  module Api
    struct CreateOrgRequest
      include JSON::Serializable
      getter org_id : String
      getter name : String
    end

    struct CreateOrgResponse
      include JSON::Serializable
      getter org_id : String
      def initialize(@org_id : String); end
    end

    struct CreateProjectRequest
      include JSON::Serializable
      getter project_id : String
      getter name : String
    end

    struct CreateProjectResponse
      include JSON::Serializable
      getter project_id : String
      def initialize(@project_id : String); end
    end

    struct AttachRolesRequest
      include JSON::Serializable
      getter roles : Array(String)
    end

    struct KickoffRequest
      include JSON::Serializable
      getter prompt : String
      getter session_id : String?
    end

    struct ErrorResponse
      include JSON::Serializable
      getter error : String
      def initialize(@error : String); end
    end
  end
end
