require "../../lfapi"

module DevTeam
  module Api
    struct AppConfig
      include LF::DI::ApplicationConfig

      def initialize(
        @system : Movie::ActorSystem(Movie::SystemMessage),
        @org_actor : Movie::ActorRef(DevTeam::OrgServiceMessage)
      )
      end

      @[LF::DI::Bean(name: "system")]
      def system : Movie::ActorSystem(Movie::SystemMessage)
        @system
      end

      @[LF::DI::Bean(name: "org_actor")]
      def org_actor : Movie::ActorRef(DevTeam::OrgServiceMessage)
        @org_actor
      end
    end

  end
end
