require "spec"
require "uuid"
require "../src/ametist"
require "../src/agency/runtime/system_message"

module Agency
  def self.spec_system : Movie::ActorSystem(SystemMessage)
    context_path = "/tmp/agency_spec_context_#{UUID.random}.sqlite3"
    graph_path = "/tmp/agency_spec_graph_#{UUID.random}.sqlite3"
    config = Movie::Config.builder
      .set("agency.context.db_path", context_path)
      .set("agency.graph.db_path", graph_path)
      .build
    Movie::ActorSystem(Agency::SystemMessage).new(Movie::Behaviors(Agency::SystemMessage).same, config)
  end
end
