require "sqlite3"

module Agency
  class ContextStore
    @db : DB::Database

    def initialize(@db_path : String)
      @db = DB.open("sqlite3:#{@db_path}")
      ensure_schema
    end

    def ensure_schema
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS session_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          name TEXT,
          tool_call_id TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
      SQL
      @db.exec "CREATE INDEX IF NOT EXISTS idx_session_events_session ON session_events(session_id)"

      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS session_summaries (
          session_id TEXT PRIMARY KEY,
          summary TEXT NOT NULL,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
      SQL

      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS session_meta (
          session_id TEXT PRIMARY KEY,
          agent_id TEXT NOT NULL,
          model TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
      SQL
    end

    def append_event(session_id : String, role : String, content : String, name : String? = nil, tool_call_id : String? = nil) : Int64
      @db.exec(
        "INSERT INTO session_events (session_id, role, content, name, tool_call_id) VALUES (?, ?, ?, ?, ?)",
        session_id, role, content, name, tool_call_id
      )
      @db.query_one("SELECT last_insert_rowid()", as: Int64)
    end

    def fetch_events(session_id : String, limit : Int32 = 100) : Array(NamedTuple(role: String, content: String, name: String?, tool_call_id: String?))
      events = [] of NamedTuple(role: String, content: String, name: String?, tool_call_id: String?)
      @db.query(
        "SELECT role, content, name, tool_call_id FROM session_events WHERE session_id = ? ORDER BY id DESC LIMIT ?",
        session_id, limit
      ) do |rs|
        rs.each do
          events << {
            role: rs.read(String),
            content: rs.read(String),
            name: rs.read(String?),
            tool_call_id: rs.read(String?),
          }
        end
      end
      events.reverse
    end

    def get_event_by_id(event_id : String) : NamedTuple(role: String, content: String, name: String?, tool_call_id: String?)?
      id = event_id.to_i64?
      return nil unless id
      @db.query_one?(
        "SELECT role, content, name, tool_call_id FROM session_events WHERE id = ?",
        id,
        as: {String, String, String?, String?}
      ).try do |row|
        {
          role: row[0],
          content: row[1],
          name: row[2],
          tool_call_id: row[3],
        }
      end
    end

    def store_summary(session_id : String, summary : String)
      @db.exec(
        "INSERT OR REPLACE INTO session_summaries (session_id, summary, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)",
        session_id, summary
      )
    end

    def get_summary(session_id : String) : String?
      @db.query_one?("SELECT summary FROM session_summaries WHERE session_id = ?", session_id, as: String)
    end

    def upsert_session_meta(session_id : String, agent_id : String, model : String)
      @db.exec(
        "INSERT INTO session_meta (session_id, agent_id, model, created_at, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         ON CONFLICT(session_id) DO UPDATE SET agent_id = excluded.agent_id, model = excluded.model, updated_at = CURRENT_TIMESTAMP",
        session_id, agent_id, model
      )
    end

    def get_session_meta(session_id : String) : NamedTuple(agent_id: String, model: String, created_at: String, updated_at: String)?
      @db.query_one?(
        "SELECT agent_id, model, created_at, updated_at FROM session_meta WHERE session_id = ?",
        session_id,
        as: {String, String, String, String}
      ).try do |row|
        {
          agent_id: row[0],
          model: row[1],
          created_at: row[2],
          updated_at: row[3],
        }
      end
    end
  end
end
