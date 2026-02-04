require "file_utils"
require "../movie"
require "./graph_store"

module Agency
  # SQLite-backed graph store extension.
  class GraphStoreExtension < Movie::Extension
    getter store : GraphStore

    def initialize(@system : Movie::AbstractActorSystem, @db_path : String)
      @store = GraphStore.new(@db_path)
    end

    def stop
      # DB::Database does not require explicit close; ignore for now.
    end
  end

  class GraphStoreExtensionId < Movie::ExtensionId(GraphStoreExtension)
    def create(system : Movie::AbstractActorSystem) : GraphStoreExtension
      path = if system.responds_to?(:config) && !system.config.empty?
        system.config.get_string("agency.graph.db_path", "data/agency_graph.sqlite3")
      else
        "data/agency_graph.sqlite3"
      end
      ensure_db_dir(path)
      GraphStoreExtension.new(system, path)
    end

    private def ensure_db_dir(path : String) : Nil
      dir = File.dirname(path)
      return if dir.empty? || dir == "."
      FileUtils.mkdir_p(dir)
    end
  end
end
