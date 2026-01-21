require "./movie"

module Ametist
  class CollectionBehavior < Movie::AbstractBehavior
  end

  class System
    def initialize
      @system = Movie::ActorSystem.new
    end
  end
end
