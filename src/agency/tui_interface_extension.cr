require "../movie"
require "./agency_extension"
require "./tui_adapter"
require "./system_message"

module Agency
  # Extension that owns the TUI adapter actor.
  class TuiInterfaceExtension < Movie::Extension
    getter system : Movie::ActorSystem(SystemMessage)
    getter agency : AgencyExtension
    getter adapter : Movie::ActorRef(TuiMessage)
    getter default_model : String

    def initialize(@system : Movie::ActorSystem(SystemMessage), @agency : AgencyExtension)
      @default_model = @agency.default_model
      @adapter = @system.spawn(TuiAdapter.behavior(@agency.manager, @default_model))
    end

    def stop
      @adapter.send_system(Movie::STOP)
    end
  end

  class TuiInterface < Movie::ExtensionId(TuiInterfaceExtension)
    def create(system : Movie::AbstractActorSystem) : TuiInterfaceExtension
      actor_system = system.as?(Movie::ActorSystem(SystemMessage))
      raise "TUI interface requires ActorSystem" unless actor_system
      agency = Agency.get(actor_system)
      TuiInterfaceExtension.new(actor_system, agency)
    end
  end
end
