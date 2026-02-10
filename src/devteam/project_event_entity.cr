require "../movie/persistence"

module DevTeam
  struct ProjectEvent
    include JSON::Serializable

    getter kind : String
    getter payload : String

    def initialize(@kind : String, @payload : String)
    end
  end

  struct ProjectEventState
    include JSON::Serializable

    getter count : Int32

    def initialize(@count : Int32 = 0)
    end
  end

  struct RecordProjectEvent
    getter event : ProjectEvent

    def initialize(@event : ProjectEvent)
    end
  end

  alias ProjectEventCommand = RecordProjectEvent

  class ProjectEventEntity < Movie::EventSourcedBehavior(ProjectEventCommand, ProjectEvent, ProjectEventState)
    def empty_state : ProjectEventState
      ProjectEventState.new(0)
    end

    def apply_event(state : ProjectEventState, event : ProjectEvent) : ProjectEventState
      ProjectEventState.new(state.count + 1)
    end

    def handle_command(state : ProjectEventState, command : ProjectEventCommand, ctx : Movie::ActorContext(ProjectEventCommand)) : Array(ProjectEvent)
      case command
      when RecordProjectEvent
        [command.event]
      else
        [] of ProjectEvent
      end
    end
  end
end
