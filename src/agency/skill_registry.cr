require "../movie"
require "./protocol"

module Agency
  struct Skill
    getter id : String
    getter description : String
    getter system_prompt : String
    getter tools : Array(ToolSpec)

    def initialize(
      @id : String,
      @description : String,
      @system_prompt : String,
      @tools : Array(ToolSpec)
    )
    end
  end

  abstract class SkillSource
    abstract def list_skills : Array(Skill)
  end

  class NullSkillSource < SkillSource
    def list_skills : Array(Skill)
      [] of Skill
    end
  end

  struct ReloadSkills
    getter reply_to : Movie::ActorRef(Bool)?

    def initialize(@reply_to : Movie::ActorRef(Bool)? = nil)
    end
  end

  struct GetSkill
    getter id : String
    getter reply_to : Movie::ActorRef(Skill?)?

    def initialize(@id : String, @reply_to : Movie::ActorRef(Skill?)? = nil)
    end
  end

  struct GetAllSkills
    getter reply_to : Movie::ActorRef(Array(Skill))?

    def initialize(@reply_to : Movie::ActorRef(Array(Skill))? = nil)
    end
  end

  alias SkillRegistryMessage = ReloadSkills | GetSkill | GetAllSkills

  class SkillRegistry < Movie::AbstractBehavior(SkillRegistryMessage)
    def self.behavior(source : SkillSource) : Movie::AbstractBehavior(SkillRegistryMessage)
      Movie::Behaviors(SkillRegistryMessage).setup do |_ctx|
        SkillRegistry.new(source)
      end
    end

    def initialize(@source : SkillSource)
      @skills = {} of String => Skill
      reload
    end

    def receive(message, ctx)
      case message
      when ReloadSkills
        reload
        reply_bool(message.reply_to, ctx, true)
      when GetSkill
        reply_skill(message.reply_to, ctx, @skills[message.id]?)
      when GetAllSkills
        reply_skills(message.reply_to, ctx, @skills.values)
      end
      Movie::Behaviors(SkillRegistryMessage).same
    end

    private def reload
      @skills.clear
      @source.list_skills.each do |skill|
        @skills[skill.id] = skill
      end
    end

    private def reply_bool(reply_to, ctx, value : Bool)
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(ctx.sender, value)
      end
    end

    private def reply_skill(reply_to, ctx, value : Skill?)
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(ctx.sender, value)
      end
    end

    private def reply_skills(reply_to, ctx, value : Array(Skill))
      if reply_to
        reply_to << value
      else
        Movie::Ask.reply_if_asked(ctx.sender, value)
      end
    end
  end
end
