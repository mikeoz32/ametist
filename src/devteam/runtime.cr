require "../movie/persistence"
require "./project_entity"
require "./project_event_entity"
require "./org_entity"

module DevTeam
  def self.project_id(org_id : String, project_id : String) : Movie::Persistence::Id
    Movie::Persistence::Id.new(ProjectEntity.name, "#{org_id}/#{project_id}")
  end

  def self.org_id(org_id : String) : Movie::Persistence::Id
    Movie::Persistence::Id.new(OrgEntity.name, org_id)
  end

  def self.project_event_id(org_id : String, project_id : String) : Movie::Persistence::Id
    Movie::Persistence::Id.new(ProjectEventEntity.name, "#{org_id}/#{project_id}")
  end

  def self.project_event_id(project_id : Movie::Persistence::Id) : Movie::Persistence::Id
    Movie::Persistence::Id.new(ProjectEventEntity.name, project_id.entity_id)
  end

  def self.register_entities(
    system : Movie::ActorSystem(Movie::SystemMessage),
    durable : Movie::DurableStateExtension,
    events : Movie::EventSourcingExtension,
    gateway : AgentGateway,
    executor : Movie::ExecutorExtension
  )
    durable.register_entity(OrgEntity) do |pid, store|
      OrgEntity.new(pid.persistence_id, store)
    end

    events.register_entity(ProjectEventEntity) do |pid, store|
      ProjectEventEntity.new(pid.persistence_id, store)
    end

    durable.register_entity(ProjectEntity) do |pid, store|
      event_ref = events.get_entity_ref_as(ProjectEventCommand, project_event_id(pid))
      ProjectEntity.new(pid, store, gateway, executor, event_ref)
    end
  end
end
