module Agency
  struct AgentProfile
    getter id : String
    getter model : String
    getter max_steps : Int32
    getter max_history : Int32
    getter memory_policy_name : String?
    getter allowed_toolsets : Array(String)

    def initialize(
      @id : String,
      @model : String = "gpt-3.5-turbo",
      @max_steps : Int32 = 8,
      @max_history : Int32 = 50,
      @memory_policy_name : String? = nil,
      @allowed_toolsets : Array(String) = [] of String
    )
    end
  end
end
