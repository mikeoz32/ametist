require "../../lfapi"
require "./messages"
require "./services"

module DevTeam
  module Api
    class OrgResource
      include LF::APIRoute

      @[LF::APIRoute::Post("/orgs")]
      def create_org(request : CreateOrgRequest, org_service : ::OrgService) : LF::Response
        LF::JSONResponse.create(org_service.create_org(request))
      end

      @[LF::APIRoute::Post("/orgs/:org_id/projects")]
      def create_project(org_id : String, request : CreateProjectRequest, org_service : ::OrgService) : LF::Response
        LF::JSONResponse.create(org_service.create_project(org_id, request))
      end

      @[LF::APIRoute::Post("/orgs/:org_id/projects/:project_id/agents")]
      def attach_roles(org_id : String, project_id : String, request : AttachRolesRequest, org_service : ::OrgService) : LF::Response
        LF::JSONResponse.create(org_service.attach_roles(org_id, project_id, request))
      end

      @[LF::APIRoute::Post("/orgs/:org_id/projects/:project_id/kickoff")]
      def kickoff(org_id : String, project_id : String, request : KickoffRequest, org_service : ::OrgService) : LF::Response
        LF::JSONResponse.create(org_service.kickoff(org_id, project_id, request))
      end

      @[LF::APIRoute::Get("/orgs/:org_id")]
      def get_org(org_id : String, org_service : ::OrgService) : LF::Response
        LF::JSONResponse.create(org_service.get_org(org_id))
      end
    end
  end
end
