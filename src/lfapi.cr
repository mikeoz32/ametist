require "http/server"
require "json"
require "fiber"

require "./lfapi/di"
require "./lfapi/trie"

# Lighting FastAPI
#
# ===============================================================================
# Router System with Trie-Based Route Matching
# ===============================================================================
#
# This module provides a high-performance HTTP router built on a radix tree (Trie)
# data structure for efficient route matching with URL parameter support.
#
# Key Features:
# -------------
# - **Fast Route Matching**: O(k) complexity where k is the path length, not number of routes
# - **URL Parameters**: Dynamic path segments using :param_name syntax
# - **Multiple Parameters**: Support for multiple params per route (e.g., /api/posts/:post_id/comments/:comment_id)
# - **HTTP Method Routing**: Multiple HTTP methods (GET, POST, PUT, DELETE, PATCH) on same path
# - **Method Filtering**: Automatic 405 Method Not Allowed for wrong methods
# - **Priority Matching**: Exact paths take priority over parameter matches
#
# Architecture:
# ------------
# 1. **Trie Module**: Radix tree implementation for path matching
#    - Node: Represents a path segment in the tree
#    - MatchResult: Contains matched node and extracted parameters
#    - Handler: Proc that receives context and route parameters
#
# 2. **LF Module**: HTTP routing layer
#    - Router: Main routing class that builds and searches the Trie
#    - Convenience methods: get(), post(), put(), delete(), patch()
#    - LFApi: HTTP::Handler wrapper for easy integration
#
# Usage Example:
# -------------
#   router = LF::Router.new
#
#   router.get("/users/:id") do |ctx, params|
#     user_id = params["id"]
#     ctx.response.print "User: #{user_id}"
#   end
#
#   router.post("/api/posts/:post_id/comments/:comment_id") do |ctx, params|
#     post_id = params["post_id"]
#     comment_id = params["comment_id"]
#     ctx.response.print "Post #{post_id}, Comment #{comment_id}"
#   end
#
# ===============================================================================
#

class Hash
  def to_t(key, type)
    {% begin %}
      case type
        {% for m, t in {to_i: Int32, to_f: Float32} %}
            when {{t.id}}.class
              self[key].{{m.id}}
          {% end %}
      else
        raise "Unsupported type: #{type}"
      end
    {% end %}
  end
end

class HTTP::Server
  @dispatcher : Fiber::ExecutionContext::Parallel = Fiber::ExecutionContext::Parallel.new("http", 24)

  protected def dispatch(io)
    @dispatcher.spawn do
      handle_client(io)
    end
  end
end

class HTTP::Server::Context
  property state : LF::DI::AnnotationApplicationContext?
end

module LF
  # Router using Trie-based route matching with parameter support
  class Route
    include HTTP::Handler
    def initialize(@match : Trie::MatchResult)
    end

    def call(context : HTTP::Server::Context)
      if @match.node
        node = @match.node.as(Trie::Node)

        # Check if the HTTP method has a handler
        handler = node.handlers[context.request.method]?

        if handler
          # Call handler with params
          handler.call(context, @match.params)
        elsif !node.handlers.empty?
          # Path exists but method not allowed
          context.response.status = HTTP::Status::METHOD_NOT_ALLOWED
          context.response.content_type = "text/plain"
          context.response.print "Method Not Allowed"
        else
          # No handlers at all
          context.response.status = HTTP::Status::NOT_FOUND
          context.response.content_type = "text/plain"
          context.response.print "Not Found"
        end
      else
        context.response.status = HTTP::Status::NOT_FOUND
        context.response.content_type = "text/plain"
        context.response.print "Not Found"
      end
    end
  end
  class Router
    include HTTP::Handler

    @root : Trie::Node

    def initialize
      @root = Trie::Node.new
    end

    # Add a route with handler
    def add(path : String, methods : Set(String) = Set{"GET"}, &handler : HTTP::Server::Context, Hash(String, String) -> Nil)
      @root.add_route(path, handler, methods)
    end

    # Add a route with handler (non-block version)
    def add(path : String, handler : Trie::Handler, methods : Set(String) = Set{"GET"})
      @root.add_route(path, handler, methods)
    end

    # Convenience method for GET routes
    def get(path : String, &handler : HTTP::Server::Context, Hash(String, String) -> Nil)
      add(path, Set{"GET"}, &handler)
    end

    # Convenience method for POST routes
    def post(path : String, &handler : HTTP::Server::Context, Hash(String, String) -> Nil)
      add(path, Set{"POST"}, &handler)
    end

    # Convenience method for PUT routes
    def put(path : String, &handler : HTTP::Server::Context, Hash(String, String) -> Nil)
      add(path, Set{"PUT"}, &handler)
    end

    # Convenience method for DELETE routes
    def delete(path : String, &handler : HTTP::Server::Context, Hash(String, String) -> Nil)
      add(path, Set{"DELETE"}, &handler)
    end

    # Convenience method for PATCH routes
    def patch(path : String, &handler : HTTP::Server::Context, Hash(String, String) -> Nil)
      add(path, Set{"PATCH"}, &handler)
    end

    def call(context : HTTP::Server::Context)
      # @root.dump
      result = @root.search(context.request.path)
      puts "Matched route: #{result}"

      route = Route.new(result)
      route.call(context)
    end
  end

  module Response
    abstract def call(context : HTTP::Server::Context)
  end

  module APIRoute
    annotation Route
    end

    annotation Get
    end

    annotation Post
    end

    annotation Put
    end

    annotation Delete
    end

    annotation Patch
    end

    macro __build_routes__
      def setup_routes(router : LF::Router)

      {% for method in @type.methods.sort_by(&.line_number) %}
        {{ puts method.annotations }}
        {{ puts method.args }}
        {% for route_method in {Get, Post, Put, Delete, Patch, Route} %}
          {% router_method = route_method.stringify.split("::")[-1].downcase.id %}
          {% router_method = "add".id if router_method == "route" %}
          {% for ann, idx in method.annotations(route_method) %}
             {{ puts ann }}
             {% path = ann[0] || ann[:path] || raise "Missing path in #{method.name}" %}
             router.{{ router_method }}({{ path }}) do |ctx, _params|
               {% for arg in method.args %}
                {% if arg.name == "request" && arg.restriction.id == "HTTP::Request" %}
                  {{ arg.name }} = ctx.request
                {% else %}
                 {{ puts arg.restriction }}
                 store = ctx.store
                 if !store.has_key?("{{ arg.name }}")
                  if _params.has_key?("{{ arg.name }}")
                    store = _params
                  else
                    raise "Missing parameter: {{ arg.name }}"
                  end
                 end
                   {{ arg.name }} : {{ arg.restriction }} = store.to_t("{{ arg.name }}", {{ arg.restriction }}).as({{ arg.restriction.id }})
                 end
                {% end %}
               {% end %}
               ctx.response.print {{ method.name }}({% for arg in method.args %}{{ arg.name }},{% end %})
             end
          {% end %}
        {% end %}
      {% end %}

      end
    end

    macro included
      macro finished
        __build_routes__
      end

      include HTTP::Handler

      def call(context)
        context.response.status = HTTP::Status::METHOD_NOT_ALLOWED
        context.response.content_type = "text/plain"
        context.response.print "Method Not Allowed"
      end
    end
  end

  class TextResponse
    include Response

    def initialize(content : String)
      @content = content
    end

    def self.create(content : String) : Response
      TextResponse.new(content).as(Response)
    end

    def call(context)
      context.response.content_type = "text/plain"
      context.response.print @content
    end
  end

  class JSONResponse
    include Response

    def initialize(content : JSON::Serializable)
      @content = content
    end

    def self.create(content : JSON::Serializable) : Response
      JSONResponse.new(content).as(Response)
    end

    def call(context)
      context.response.content_type = "application/json"
      @content.to_json(context.response)
    end
  end

  class LFApi
    include HTTP::Handler

    @router : Router

    def initialize(&block : Router -> Nil)
      @router = Router.new
      block.call(@router)
    end

    def call(context)
      @router.call(context)
    end
  end
end
