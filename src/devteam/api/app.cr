require "../../lfapi"
require "../org_service"
require "./config"
require "./messages"
require "./resources"

module DevTeam
  module Api
    class App
      include HTTP::Handler

      def initialize(
        @system : Movie::ActorSystem(Movie::SystemMessage),
        @org_service : Movie::ActorRef(DevTeam::OrgServiceMessage),
        @api_key : String
      )
        @router = LF::Router.new
        OrgResource.new.setup_routes(@router)

        @ctx = LF::DI::AnnotationApplicationContext.new
        @ctx.register(AppConfig.new(@system, @org_service))
        @ctx.register(LF::DI::AutowiredApplicationConfig.new)
      end

      def call(context : HTTP::Server::Context)
        unless authorized?(context)
          respond_json(context, HTTP::Status::UNAUTHORIZED, ErrorResponse.new("unauthorized"))
          return
        end

        context.response.content_type = "application/json"
        context.state = @ctx
        @router.call(context)
      rescue e : LF::BadRequest
        respond_json(context, HTTP::Status::BAD_REQUEST, ErrorResponse.new(e.message || "bad request"))
      rescue e : Exception
        respond_json(context, HTTP::Status::INTERNAL_SERVER_ERROR, ErrorResponse.new("internal error"))
      end

      private def authorized?(ctx : HTTP::Server::Context) : Bool
        return true if @api_key.empty?
        header_key = ctx.request.headers["X-API-Key"]?
        return true if header_key == @api_key
        if query = ctx.request.query_params
          return true if query["api_key"]? == @api_key
        end
        false
      end

      private def respond_json(ctx : HTTP::Server::Context, status : HTTP::Status, payload : JSON::Serializable)
        ctx.response.status = status
        ctx.response.content_type = "application/json"
        payload.to_json(ctx.response)
      end
    end
  end
end
