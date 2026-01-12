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
    call_next(context)
  ensure
    context.state.as(LF::DI::AnnotationApplicationContext).exit unless context.state.nil?
  end
end

@[LF::DI::Service]
class TestService
  def initialize(@database : Ametist::Database)
  end
end

struct AmetistConfig
  include LF::DI::ApplicationConfig


  @[LF::DI::Bean]
  def name : String
    "test"
  end

  @[LF::DI::Bean(name: "database")]
  def database(name : String) : Ametist::Database
    puts "Database name: #{name}"
    Ametist::Database.new
  end
end

def main
  ctx = LF::DI::AnnotationApplicationContext.new
  auto = LF::DI::AutowiredApplicationConfig.new
  ctx.register(AmetistConfig.new)
  ctx.register(auto)
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
