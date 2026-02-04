require "file_utils"
require "../movie"
require "./context_store"

module Agency
  # SQLite-backed context store extension for session logs and summaries.
  class ContextStoreExtension < Movie::Extension
    getter store : ContextStore

    def initialize(@system : Movie::AbstractActorSystem, @db_path : String)
      @store = ContextStore.new(@db_path)
    end

    def stop
      # DB::Database does not require explicit close; ignore for now.
    end
  end

  class ContextStoreExtensionId < Movie::ExtensionId(ContextStoreExtension)
    def create(system : Movie::AbstractActorSystem) : ContextStoreExtension
      path = if system.responds_to?(:config) && !system.config.empty?
        system.config.get_string("agency.context.db_path", "data/agency_context.sqlite3")
      else
        "data/agency_context.sqlite3"
      end
      ensure_db_dir(path)
      ContextStoreExtension.new(system, path)
    end

    private def ensure_db_dir(path : String) : Nil
      dir = File.dirname(path)
      return if dir.empty? || dir == "."
      FileUtils.mkdir_p(dir)
    end
  end
end
