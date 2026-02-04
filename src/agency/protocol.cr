require "json"
require "uuid"

module Agency
  enum Role
    System
    User
    Assistant
    Tool
  end

  # Canonical message type used by the agent loop.
  struct Message
    getter role : Role
    getter content : String
    getter name : String?
    getter tool_call_id : String?

    def initialize(@role : Role, @content : String, @name : String? = nil, @tool_call_id : String? = nil)
    end
  end

  # JSON-Schema-based tool definition (open standard).
  struct ToolSpec
    getter name : String
    getter description : String?
    getter parameters : JSON::Any

    def initialize(@name : String, @description : String? = nil, @parameters : JSON::Any = JSON.parse(%({"type":"object"})))
    end

    def to_h
      {
        "name" => @name,
        "description" => (@description || ""),
        "parameters" => @parameters,
      }
    end
  end

  struct ToolCall
    getter id : String
    getter name : String
    getter arguments : JSON::Any

    def initialize(@name : String, @arguments : JSON::Any, @id : String = UUID.random.to_s)
    end
  end

  struct ToolResult
    getter id : String
    getter name : String
    getter content : String

    def initialize(@id : String, @name : String, @content : String)
    end
  end

  struct LLMOutput
    getter content : String?
    getter tool_calls : Array(ToolCall)

    def initialize(@content : String? = nil, @tool_calls : Array(ToolCall) = [] of ToolCall)
    end

    def final?
      @tool_calls.empty?
    end
  end

  module Protocol
    # ReAct-style system prompt with JSON tool specs and strict JSON output.
    def self.system_prompt(tools : Array(ToolSpec)) : String
      tools_json = tools.map(&.to_h).to_json
      <<-TEXT
      You are a tool-using agent. Use the tools when needed.

      TOOLS (JSON Schema):
      #{tools_json}

      OUTPUT FORMAT (JSON ONLY):
      - For final answers:
        {"type":"final","content":"..."}
      - For tool calls:
        {"type":"tool_call","tool_calls":[{"id":"...","name":"tool_name","arguments":{...}}]}

      Never output non-JSON text.
      TEXT
    end

    # Attempts to parse the LLM response as JSON, falling back to plain text.
    def self.parse_output(text : String) : LLMOutput
      json = begin
        JSON.parse(text)
      rescue
        return LLMOutput.new(text, [] of ToolCall)
      end

      obj = json.as_h?
      return LLMOutput.new(text, [] of ToolCall) unless obj

      type = obj["type"]?.try(&.as_s?) || ""
      if type == "tool_call" || obj.has_key?("tool_calls")
        calls = parse_tool_calls(obj["tool_calls"]?)
        return LLMOutput.new(nil, calls)
      end

      content = obj["content"]?.try(&.as_s?) || text
      LLMOutput.new(content, [] of ToolCall)
    end

    private def self.parse_tool_calls(node : JSON::Any?) : Array(ToolCall)
      return [] of ToolCall if node.nil?
      calls = [] of ToolCall
      case node.raw
      when Array
        node.as_a.each do |entry|
          calls << build_tool_call(entry) if entry.as_h?
        end
      when Hash
        calls << build_tool_call(node) if node.as_h?
      end
      calls
    end

    private def self.build_tool_call(node : JSON::Any) : ToolCall
      h = node.as_h
      id = h["id"]?.try(&.as_s?) || UUID.random.to_s
      name = h["name"]?.try(&.as_s?) || "unknown"
      args = h["arguments"]? || JSON::Any.new({} of String => JSON::Any)
      ToolCall.new(name, args, id)
    end
  end
end
