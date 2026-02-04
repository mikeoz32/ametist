require "sqlite3"

module Agency
  class StateStore
    @db : DB::Database

    def initialize(@db_path : String)
      @db = DB.open("sqlite3:#{@db_path}")
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS kv (
          key TEXT PRIMARY KEY,
          value TEXT
        );
      SQL
    end

    def set(key : String, value : String) : Nil
      @db.exec("INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)", key, value)
    end

    def get(key : String) : String?
      @db.query_one?("SELECT value FROM kv WHERE key = ?", key, as: String)
    end
  end
end
