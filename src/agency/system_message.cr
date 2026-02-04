module Agency
  struct TuiInput
    getter prompt : String

    def initialize(@prompt : String)
    end
  end

  struct TuiHelp
  end

  struct TuiSetSession
    getter session_id : String

    def initialize(@session_id : String)
    end
  end

  struct TuiSetModel
    getter model : String

    def initialize(@model : String)
    end
  end

  struct TuiSetAgent
    getter agent_id : String

    def initialize(@agent_id : String)
    end
  end

  struct TuiReloadSkills
  end

  struct TuiListSkills
  end

  alias TuiRootMessage = TuiInput | TuiHelp | TuiSetSession | TuiSetModel | TuiSetAgent | TuiReloadSkills | TuiListSkills
  alias SystemMessage = TuiRootMessage
end
