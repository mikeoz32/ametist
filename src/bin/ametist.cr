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
    # Cleanup per-request DI context
    if state = context.state
      state.as(LF::DI::AnnotationApplicationContext).exit
    end
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
    Ametist::Database.new
  end

end

def main
  ctx = LF::DI::AnnotationApplicationContext.new
  auto = LF::DI::AutowiredApplicationConfig.new
  ctx.register(AmetistConfig.new)
  ctx.register(auto)
  api = LF::LFApi.new do |router|
    CollectionsResource.new.setup_routes(router)
  end
  server = HTTP::Server.new([
    HTTP::LogHandler.new,
    DatabaseInjector.new(ctx),
    api,
  ])

  address = server.bind_tcp(9999)
  Log.info { "Starting Ametist API at #{address}" }
  server.listen
end

main
