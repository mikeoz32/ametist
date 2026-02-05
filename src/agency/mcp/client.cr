require "json"
require "../../json_rpc"
require "./types"

module Agency
  module MCP
    class Client
      getter server_info : ServerInfo?
      getter server_capabilities : Capabilities?
      getter protocol_version : String?

      def initialize(
        transport : JsonRpc::Transport,
        @client_name : String,
        @client_version : String,
        @roots : Array(Root) = [] of Root
      )
        @rpc = JsonRpc::Client.new(transport)
        @server_info = nil
        @server_capabilities = nil
        @protocol_version = nil
        @initialized = false
        @started = false

        register_handlers
      end

      def start
        return if @started
        @started = true
        @rpc.start
      end

      def initialize_connection : Bool
        return true if @initialized
        params = InitializeParams.new(
          "2025-11-25",
          ClientCapabilities.new(
            roots: RootsCapability.new(false),
            sampling: ToggleCapability.new(false),
            elicitation: ToggleCapability.new(false)
          ),
          ClientInfo.new(@client_name, @client_version)
        )

        result = decode(InitializeResult, @rpc.request("initialize", encode(params)))
        @protocol_version = result.protocol_version
        @server_capabilities = result.capabilities
        @server_info = result.server_info
        @rpc.notify("notifications/initialized")
        @initialized = true
        true
      end

      def initialized? : Bool
        @initialized
      end

      def list_tools(cursor : String? = nil) : ListToolsResult
        ensure_initialized
        result = if cursor
                   params = ListParams.new(cursor)
                   decode(ListToolsResult, @rpc.request("tools/list", encode(params)))
                 else
                   decode(ListToolsResult, @rpc.request("tools/list"))
                 end
        result
      end

      def call_tool(name : String, arguments : JSON::Any) : ToolCallResult
        ensure_initialized
        params = ToolCallParams.new(name, arguments)
        decode(ToolCallResult, @rpc.request("tools/call", encode(params)))
      end

      def list_resources(cursor : String? = nil) : ListResourcesResult
        ensure_initialized
        if cursor
          params = ListParams.new(cursor)
          decode(ListResourcesResult, @rpc.request("resources/list", encode(params)))
        else
          decode(ListResourcesResult, @rpc.request("resources/list"))
        end
      end

      def list_resource_templates(cursor : String? = nil) : ListResourceTemplatesResult
        ensure_initialized
        if cursor
          params = ListParams.new(cursor)
          decode(ListResourceTemplatesResult, @rpc.request("resources/templates/list", encode(params)))
        else
          decode(ListResourceTemplatesResult, @rpc.request("resources/templates/list"))
        end
      end

      def read_resource(uri : String) : ReadResourceResult
        ensure_initialized
        params = ResourceParams.new(uri)
        decode(ReadResourceResult, @rpc.request("resources/read", encode(params)))
      end

      def subscribe_resource(uri : String) : EmptyResult
        ensure_initialized
        params = ResourceParams.new(uri)
        decode(EmptyResult, @rpc.request("resources/subscribe", encode(params)))
      end

      def unsubscribe_resource(uri : String) : EmptyResult
        ensure_initialized
        params = ResourceParams.new(uri)
        decode(EmptyResult, @rpc.request("resources/unsubscribe", encode(params)))
      end

      def list_prompts(cursor : String? = nil) : ListPromptsResult
        ensure_initialized
        if cursor
          params = ListParams.new(cursor)
          decode(ListPromptsResult, @rpc.request("prompts/list", encode(params)))
        else
          decode(ListPromptsResult, @rpc.request("prompts/list"))
        end
      end

      def get_prompt(name : String, arguments : JSON::Any? = nil) : GetPromptResult
        ensure_initialized
        params = GetPromptParams.new(name, arguments)
        decode(GetPromptResult, @rpc.request("prompts/get", encode(params)))
      end

      def complete(params : CompletionParams) : CompletionResult
        ensure_initialized
        decode(CompletionResult, @rpc.request("completion/complete", encode(params)))
      end

      def set_log_level(level : String) : EmptyResult
        ensure_initialized
        params = LogLevelParams.new(level)
        decode(EmptyResult, @rpc.request("logging/setLevel", encode(params)))
      end

      private def ensure_initialized
        initialize_connection unless @initialized
      end

      private def register_handlers
        @rpc.register_request("roots/list") do |_params|
          encode(RootListResult.new(@roots))
        end

        @rpc.register_request("ping") do |_params|
          JSON::Any.new({} of String => JSON::Any)
        end
      end

      private def encode(value) : JSON::Any
        JSON.parse(value.to_json)
      end

      private def decode(type : T.class, value : JSON::Any) : T forall T
        T.from_json(value.to_json)
      end
    end
  end
end
