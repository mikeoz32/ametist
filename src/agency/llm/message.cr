module Agency
  # Simple message that carries the LLM response text.
  struct LLMResult
    getter content : String

    def initialize(@content : String)
    end
  end
end
