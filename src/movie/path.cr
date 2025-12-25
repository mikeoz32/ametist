module Movie
  struct Address
    getter protocol : String
    getter system : String
    getter host : String?
    getter port : Int32?

    def initialize(@protocol : String, @system : String, @host : String?, @port : Int32?)
    end
  end

  struct ActorPath
    @address : Address
    getter name : String
    @parent : ActorPath?

    def initialize(@address : Address, @name : String, @parent : ActorPath?)
    end

  end
end
