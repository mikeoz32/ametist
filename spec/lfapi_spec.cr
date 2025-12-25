require "./spec_helper"
require "../src/lfapi"

class JsonModel
  include JSON::Serializable

  property id : Int32
  property name : String

  def initialize(@id : Int32, @name : String)
  end
end

describe "Trie" do
  describe "Node" do
    it "adds and searches exact routes" do
      t = Trie::Node.new
      dummy_handler = ->(ctx : HTTP::Server::Context, params : Hash(String, String)) { }

      t.add_route("/hello", dummy_handler)
      t.add_route("/hi", dummy_handler)
      t.add_route("/hi/user", dummy_handler)

      result = t.search("/hello")
      result.node.should_not be_nil
      result.params.should be_empty

      result = t.search("/hi")
      result.node.should_not be_nil
      result.params.should be_empty

      result = t.search("/hi/user")
      result.node.should_not be_nil
      result.params.should be_empty
    end

    it "matches routes with single parameter" do
      t = Trie::Node.new
      dummy_handler = ->(ctx : HTTP::Server::Context, params : Hash(String, String)) { }

      t.add_route("/users/:id", dummy_handler)

      result = t.search("/users/42")
      result.node.should_not be_nil
      result.params["id"].should eq("42")

      result = t.search("/users/john")
      result.node.should_not be_nil
      result.params["id"].should eq("john")
    end

    it "matches routes with multiple parameters" do
      t = Trie::Node.new
      dummy_handler = ->(ctx : HTTP::Server::Context, params : Hash(String, String)) { }

      t.add_route("/api/posts/:post_id/comments/:comment_id", dummy_handler)

      result = t.search("/api/posts/42/comments/7")
      result.node.should_not be_nil
      result.params["post_id"].should eq("42")
      result.params["comment_id"].should eq("7")

      result = t.search("/api/posts/hello-world/comments/99")
      result.node.should_not be_nil
      result.params["post_id"].should eq("hello-world")
      result.params["comment_id"].should eq("99")
    end

    it "returns nil for non-existent routes" do
      t = Trie::Node.new
      dummy_handler = ->(ctx : HTTP::Server::Context, params : Hash(String, String)) { }

      t.add_route("/hello", dummy_handler)

      result = t.search("/notfound")
      result.node.should be_nil
    end

    it "prioritizes exact matches over parameter matches" do
      t = Trie::Node.new
      dummy_handler1 = ->(ctx : HTTP::Server::Context, params : Hash(String, String)) {
        ctx.response.print "exact"
      }
      dummy_handler2 = ->(ctx : HTTP::Server::Context, params : Hash(String, String)) {
        ctx.response.print "param"
      }

      t.add_route("/users/list", dummy_handler1)
      t.add_route("/users/:id", dummy_handler2)

      result = t.search("/users/list")
      result.node.should_not be_nil
      result.params.should be_empty

      result = t.search("/users/123")
      result.node.should_not be_nil
      result.params["id"].should eq("123")
    end
  end
end

describe "LF::Router" do
  it "routes GET requests correctly" do
    router = LF::Router.new

    router.get("/hello") do |ctx, _params|
      ctx.response.content_type = "text/plain"
      ctx.response.print "Hello World!"
    end

    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/hello")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    router.call(context)
    response.close

    result_output = io.to_s
    body = result_output.split("\r\n\r\n", 2)[1]
    body.should eq("Hello World!")
    response.status.should eq(HTTP::Status::OK)
  end

  it "extracts route parameters" do
    router = LF::Router.new

    router.get("/users/:id") do |ctx, params|
      ctx.response.content_type = "text/plain"
      ctx.response.print "User ID: #{params["id"]}"
    end

    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/users/123")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    router.call(context)
    response.close

    body = io.to_s.split("\r\n\r\n", 2)[1]
    body.should eq("User ID: 123")
  end

  it "extracts multiple parameters" do
    router = LF::Router.new

    router.get("/api/posts/:post_id/comments/:comment_id") do |ctx, params|
      ctx.response.content_type = "text/plain"
      ctx.response.print "Post #{params["post_id"]}, Comment #{params["comment_id"]}"
    end

    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/api/posts/42/comments/7")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    router.call(context)
    response.close

    body = io.to_s.split("\r\n\r\n", 2)[1]
    body.should eq("Post 42, Comment 7")
  end

  it "supports different HTTP methods on same path" do
    router = LF::Router.new

    router.get("/data") do |ctx, _params|
      ctx.response.print "GET data"
    end

    router.post("/data") do |ctx, _params|
      ctx.response.print "POST data"
    end

    # Test GET
    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/data")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    router.call(context)
    response.close
    body = io.to_s.split("\r\n\r\n", 2)[1]
    body.should eq("GET data")

    # Test POST
    io = IO::Memory.new
    request = HTTP::Request.new("POST", "/data")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    router.call(context)
    response.close
    body = io.to_s.split("\r\n\r\n", 2)[1]
    body.should eq("POST data")
  end

  it "returns 404 for non-existent routes" do
    router = LF::Router.new

    router.get("/hello") do |ctx, _params|
      ctx.response.print "Hello"
    end

    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/notfound")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    router.call(context)
    response.close

    response.status.should eq(HTTP::Status::NOT_FOUND)
  end

  it "returns 405 for wrong HTTP method" do
    router = LF::Router.new

    router.post("/data") do |ctx, _params|
      ctx.response.print "POST only"
    end

    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/data")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    router.call(context)
    response.close

    response.status.should eq(HTTP::Status::METHOD_NOT_ALLOWED)
  end

  it "supports all HTTP method convenience methods" do
    router = LF::Router.new

    router.get("/get") { |ctx, _| ctx.response.print "GET" }
    router.post("/post") { |ctx, _| ctx.response.print "POST" }
    router.put("/put") { |ctx, _| ctx.response.print "PUT" }
    router.delete("/delete") { |ctx, _| ctx.response.print "DELETE" }
    router.patch("/patch") { |ctx, _| ctx.response.print "PATCH" }

    methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
    methods.each do |method|
      io = IO::Memory.new
      request = HTTP::Request.new(method, "/#{method.downcase}")
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)
      router.call(context)
      response.close
      body = io.to_s.split("\r\n\r\n", 2)[1]
      body.should eq(method)
    end
  end
end

describe "LF::LFApi" do
  it "works as HTTP::Handler" do
    app = LF::LFApi.new do |router|
      router.get("/hello") do |ctx, _params|
        ctx.response.content_type = "text/plain"
        ctx.response.print "Hello from LFApi!"
      end
    end

    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/hello")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    app.call(context)
    response.close

    body = io.to_s.split("\r\n\r\n", 2)[1]
    body.should eq("Hello from LFApi!")
  end

  it "handles JSON responses" do
    app = LF::LFApi.new do |router|
      router.get("/json") do |ctx, _params|
        ctx.response.content_type = "application/json"
        JsonModel.new(1, "John").to_json(ctx.response)
      end
    end

    io = IO::Memory.new
    request = HTTP::Request.new("GET", "/json")
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)

    app.call(context)
    response.close

    result_output = io.to_s
    body = if result_output.includes?("\r\n\r\n")
      result_output.split("\r\n\r\n", 2)[1]
    else
      result_output
    end

    # Just check the body contains the expected JSON structure
    body.should contain("\"id\"")
    body.should contain("\"name\"")
    body.should contain("John")
  end
end
