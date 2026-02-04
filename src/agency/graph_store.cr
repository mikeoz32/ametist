require "sqlite3"
require "../movie"

module Agency
  struct GraphNode
    getter id : String
    getter type : String
    getter data : String?

    def initialize(@id : String, @type : String, @data : String? = nil)
    end
  end

  struct GraphEdge
    getter id : String
    getter from_id : String
    getter to_id : String
    getter type : String
    getter data : String?

    def initialize(@id : String, @from_id : String, @to_id : String, @type : String, @data : String? = nil)
    end
  end

  class GraphStore
    @db : DB::Database

    def initialize(@db_path : String)
      @db = DB.open("sqlite3:#{@db_path}")
      ensure_schema
    end

    def ensure_schema
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS nodes (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          data TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
      SQL
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS edges (
          id TEXT PRIMARY KEY,
          from_id TEXT NOT NULL,
          to_id TEXT NOT NULL,
          type TEXT NOT NULL,
          data TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(from_id) REFERENCES nodes(id),
          FOREIGN KEY(to_id) REFERENCES nodes(id)
        );
      SQL
      @db.exec "CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_id)"
      @db.exec "CREATE INDEX IF NOT EXISTS idx_edges_to ON edges(to_id)"
    end

    def add_node(id : String, type : String, data : String? = nil)
      @db.exec("INSERT OR REPLACE INTO nodes (id, type, data) VALUES (?, ?, ?)", id, type, data)
    end

    def add_edge(id : String, from_id : String, to_id : String, type : String, data : String? = nil)
      @db.exec("INSERT OR REPLACE INTO edges (id, from_id, to_id, type, data) VALUES (?, ?, ?, ?, ?)", id, from_id, to_id, type, data)
    end

    def get_node(id : String) : GraphNode?
      @db.query_one?("SELECT id, type, data FROM nodes WHERE id = ?", id, as: {String, String, String?}).try do |row|
        GraphNode.new(row[0], row[1], row[2])
      end
    end

    def neighbors(node_id : String) : Array(GraphNode)
      nodes = [] of GraphNode
      @db.query("SELECT n.id, n.type, n.data FROM edges e JOIN nodes n ON e.to_id = n.id WHERE e.from_id = ?", node_id) do |rs|
        rs.each do
          nodes << GraphNode.new(rs.read(String), rs.read(String), rs.read(String?))
        end
      end
      nodes
    end
  end
end
