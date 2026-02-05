require "json"

module Agency
  module MCP
    class ClientInfo
      include JSON::Serializable
      property name : String
      property version : String

      def initialize(@name : String, @version : String)
      end
    end

    class ServerInfo
      include JSON::Serializable
      property name : String
      property version : String?
    end

    class ToggleCapability
      include JSON::Serializable
      property enabled : Bool?

      def initialize(@enabled : Bool? = nil)
      end
    end

    class RootsCapability
      include JSON::Serializable
      @[JSON::Field(key: "listChanged")]
      property list_changed : Bool?

      def initialize(@list_changed : Bool? = nil)
      end
    end

    class Capabilities
      include JSON::Serializable
      property tools : JSON::Any?
      property resources : JSON::Any?
      property prompts : JSON::Any?
      property logging : JSON::Any?
      property roots : RootsCapability?
      property sampling : ToggleCapability?
      property elicitation : ToggleCapability?

      def initialize(
        @tools : JSON::Any? = nil,
        @resources : JSON::Any? = nil,
        @prompts : JSON::Any? = nil,
        @logging : JSON::Any? = nil,
        @roots : RootsCapability? = nil,
        @sampling : ToggleCapability? = nil,
        @elicitation : ToggleCapability? = nil
      )
      end
    end

    class ClientCapabilities
      include JSON::Serializable
      property roots : RootsCapability?
      property sampling : ToggleCapability?
      property elicitation : ToggleCapability?

      def initialize(
        @roots : RootsCapability? = nil,
        @sampling : ToggleCapability? = nil,
        @elicitation : ToggleCapability? = nil
      )
      end
    end

    class InitializeParams
      include JSON::Serializable
      @[JSON::Field(key: "protocolVersion")]
      property protocol_version : String
      property capabilities : ClientCapabilities
      @[JSON::Field(key: "clientInfo")]
      property client_info : ClientInfo

      def initialize(@protocol_version : String, @capabilities : ClientCapabilities, @client_info : ClientInfo)
      end
    end

    class InitializeResult
      include JSON::Serializable
      @[JSON::Field(key: "protocolVersion")]
      property protocol_version : String?
      property capabilities : Capabilities?
      @[JSON::Field(key: "serverInfo")]
      property server_info : ServerInfo?
    end

    class Root
      include JSON::Serializable
      property uri : String
      property name : String?

      def initialize(@uri : String, @name : String? = nil)
      end
    end

    class RootListResult
      include JSON::Serializable
      property roots : Array(Root)

      def initialize(@roots : Array(Root))
      end
    end

    class Tool
      include JSON::Serializable
      property name : String
      property title : String?
      property description : String?
      @[JSON::Field(key: "inputSchema")]
      property input_schema : JSON::Any
      @[JSON::Field(key: "outputSchema")]
      property output_schema : JSON::Any?
      property annotations : JSON::Any?

      def initialize(
        @name : String,
        @description : String?,
        @input_schema : JSON::Any,
        @title : String? = nil,
        @output_schema : JSON::Any? = nil,
        @annotations : JSON::Any? = nil
      )
      end
    end

    class ListParams
      include JSON::Serializable
      property cursor : String?

      def initialize(@cursor : String? = nil)
      end
    end

    class ListToolsResult
      include JSON::Serializable
      property tools : Array(Tool)
      @[JSON::Field(key: "nextCursor")]
      property next_cursor : String?
    end

    class ToolCallParams
      include JSON::Serializable
      property name : String
      property arguments : JSON::Any

      def initialize(@name : String, @arguments : JSON::Any)
      end
    end

    class ToolCallResult
      include JSON::Serializable
      property content : Array(JSON::Any)
      @[JSON::Field(key: "isError")]
      property is_error : Bool?
      @[JSON::Field(key: "structuredContent")]
      property structured_content : JSON::Any?
    end

    class Resource
      include JSON::Serializable
      property uri : String
      property name : String?
      property title : String?
      property description : String?
      @[JSON::Field(key: "mimeType")]
      property mime_type : String?
      property annotations : JSON::Any?
    end

    class ListResourcesResult
      include JSON::Serializable
      property resources : Array(Resource)
      @[JSON::Field(key: "nextCursor")]
      property next_cursor : String?
    end

    class ResourceTemplate
      include JSON::Serializable
      @[JSON::Field(key: "uriTemplate")]
      property uri_template : String
      property name : String
      property title : String?
      property description : String?
      @[JSON::Field(key: "mimeType")]
      property mime_type : String?
      property annotations : JSON::Any?
    end

    class ListResourceTemplatesResult
      include JSON::Serializable
      @[JSON::Field(key: "resourceTemplates")]
      property resource_templates : Array(ResourceTemplate)
      @[JSON::Field(key: "nextCursor")]
      property next_cursor : String?
    end

    class ResourceContents
      include JSON::Serializable
      property uri : String
      property name : String?
      property title : String?
      property text : String?
      @[JSON::Field(key: "mimeType")]
      property mime_type : String?
      property blob : String?
    end

    class ReadResourceResult
      include JSON::Serializable
      property contents : Array(ResourceContents)
    end

    class ResourceParams
      include JSON::Serializable
      property uri : String

      def initialize(@uri : String)
      end
    end

    class PromptArgument
      include JSON::Serializable
      property name : String
      property description : String?
      property required : Bool?
    end

    class Prompt
      include JSON::Serializable
      property name : String
      property title : String?
      property description : String?
      property arguments : Array(PromptArgument)?
    end

    class ListPromptsResult
      include JSON::Serializable
      property prompts : Array(Prompt)
      @[JSON::Field(key: "nextCursor")]
      property next_cursor : String?
    end

    class PromptMessage
      include JSON::Serializable
      property role : String
      property content : JSON::Any
    end

    class GetPromptParams
      include JSON::Serializable
      property name : String
      property arguments : JSON::Any?

      def initialize(@name : String, @arguments : JSON::Any? = nil)
      end
    end

    class GetPromptResult
      include JSON::Serializable
      property description : String?
      property messages : Array(PromptMessage)
    end

    class LogLevelParams
      include JSON::Serializable
      property level : String

      def initialize(@level : String)
      end
    end

    class CompletionReference
      include JSON::Serializable
      property type : String
      property name : String?
      property uri : String?

      def initialize(@type : String, @name : String? = nil, @uri : String? = nil)
      end
    end

    class CompletionArgument
      include JSON::Serializable
      property name : String
      property value : String

      def initialize(@name : String, @value : String)
      end
    end

    class CompletionContext
      include JSON::Serializable
      property arguments : Hash(String, String)?

      def initialize(@arguments : Hash(String, String)? = nil)
      end
    end

    class CompletionParams
      include JSON::Serializable
      property ref : CompletionReference
      property argument : CompletionArgument
      property context : CompletionContext?

      def initialize(
        @ref : CompletionReference,
        @argument : CompletionArgument,
        @context : CompletionContext? = nil
      )
      end
    end

    class Completion
      include JSON::Serializable
      property values : Array(String)
      property total : Int32?
      @[JSON::Field(key: "hasMore")]
      property has_more : Bool?
    end

    class CompletionResult
      include JSON::Serializable
      property completion : Completion
    end

    class EmptyResult
      include JSON::Serializable
    end
  end
end
