require "../lfapi"
require "../ametist"
require "json"

class CreateCollectionRequest
  include JSON::Serializable

  property name : String
  property description : String
end

class CollectionsResource
  include LF::APIRoute

  @[LF::APIRoute::Get("/collections")]
  def list_collections(request : HTTP::Request)
    Ametist::CollectionSchema.new("test", [] of Ametist::FieldSchema)
  end

  @[LF::APIRoute::Post("/collections")]
  def create_collection(collection : CreateCollectionRequest)
    collection.name
  end
end

class DatabaseInjector
  include HTTP::Handler

  def initialize(@ctx : LF::DI::AnnotationApplicationContext)
  end

  def call(context)
    context.state = @ctx.enter_scope("request")
    # TODO - Implement entering to request scope
    call_next(context)
  ensure
    context.state.as(LF::DI::AnnotationApplicationContext).exit unless context.state.nil?
  end
end

struct AmetistConfig
  include LF::DI::ApplicationConfig

  @[LF::DI::Bean(name: "database")]
  def database : Ametist::Database
    Ametist::Database.new
  end
end

def main
  ctx = LF::DI::AnnotationApplicationContext.new
  ctx.register(AmetistConfig.new)
  ctx.add_bean(name: "dbconfig", type: String) { |_| "test" }
  ctx.add_bean(name: "database", scope: "singleton", type: Ametist::Database) do |ctx|
    puts ctx.get_bean("dbconfig", String)
    Ametist::Database.new
  end
  database = ctx.get_bean("database", Ametist::Database)
  puts "ctx.get_bean(#{database}, Ametist::Database)"
  api = LF::LFApi.new do |router|
    CollectionsResource.new.setup_routes(router)
  end
  server = HTTP::Server.new([
    HTTP::LogHandler.new,
    DatabaseInjector.new(ctx),
    api,
  ])

  address = server.bind_tcp(9999)
  puts "Starting Ametist api at #{address}"
  server.listen
end

main
