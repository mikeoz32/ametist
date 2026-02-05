require "yaml"
require "./registry"

module Agency
  class SkillLoadError < Exception
    getter path : String

    def initialize(@path : String, message : String)
      super("#{message} (#{path})")
    end
  end

  class FilesystemSkillSource < SkillSource
    def self.default_roots(base_dir : String = Dir.current, home : String = ENV["HOME"]? || "") : Array(String)
      roots = [] of String
      roots << File.join(base_dir, ".claude", "skills")
      roots << File.join(base_dir, ".opencode", "skill")
      roots << File.join(base_dir, ".codex", "skills")
      roots << File.join(base_dir, ".github", "copilot", "skills")
      unless home.empty?
        roots << File.join(home, ".claude", "skills")
        roots << File.join(home, ".config", "opencode", "skill")
        roots << File.join(home, ".codex", "skills")
        roots << File.join(home, ".config", "copilot", "skills")
      end
      roots
    end

    def initialize(@roots : Array(String))
    end

    def list_skills : Array(Skill)
      skills = {} of String => Skill
      each_skill_file do |path|
        skill = load_skill(path)
        skills[skill.id] = skill
      end
      skills.values
    end

    private def each_skill_file(&block : String ->)
      @roots.each do |root|
        expanded = File.expand_path(root)
        if File.file?(expanded)
          next unless File.basename(expanded) == "SKILL.md"
          yield expanded
          next
        end
        next unless Dir.exists?(expanded)
        Dir.glob(File.join(expanded, "**", "SKILL.md")).sort.each do |path|
          yield path
        end
      end
    end

    private def load_skill(path : String) : Skill
      content = File.read(path)
      if front = parse_front_matter(content, path)
        front_matter, body = front
        fields = parse_front_yaml(front_matter, path)
        id = string_field(fields, "name", path) || default_id(path)
        description = string_field(fields, "description", path)
        if description.nil?
          if meta_any = fields["metadata"]?
            description = nested_string_field(meta_any, "short-description", path)
          end
        end
        system_prompt = body.lstrip
        Skill.new(id, description || "", system_prompt, [] of ToolSpec)
      else
        id = default_id(path)
        Skill.new(id, "", content, [] of ToolSpec)
      end
    end

    private def default_id(path : String) : String
      File.basename(File.dirname(path))
    end

    private def parse_front_matter(content : String, path : String) : {String, String}?
      return nil unless content.starts_with?("---")
      lines = content.split(/\r?\n/)
      return nil unless lines.first.strip == "---"
      close_index = nil
      lines[1..].each_with_index do |line, idx|
        if line.strip == "---"
          close_index = idx + 1
          break
        end
      end
      raise SkillLoadError.new(path, "Front matter missing closing delimiter") unless close_index
      front = lines[1...close_index].join("\n")
      body = ""
      if close_index + 1 < lines.size
        body = lines[(close_index + 1)..].join("\n")
      end
      {front, body}
    end

    private def parse_front_yaml(front : String, path : String) : Hash(String, YAML::Any)
      begin
        yaml = YAML.parse(front)
      rescue ex
        raise SkillLoadError.new(path, "Invalid front matter: #{ex.message}")
      end
      map_any = yaml.as_h? || raise SkillLoadError.new(path, "Front matter must be a mapping")
      map = {} of String => YAML::Any
      map_any.each do |key_any, value|
        key = key_any.as_s?
        raise SkillLoadError.new(path, "Front matter key must be a string") unless key
        map[key] = value
      end
      map
    end

    private def string_field(map : Hash(String, YAML::Any), key : String, path : String) : String?
      return nil unless value = map[key]?
      string = value.as_s?
      raise SkillLoadError.new(path, "Front matter '#{key}' must be a string") unless string
      string
    end

    private def nested_string_field(value : YAML::Any, key : String, path : String) : String?
      map_any = value.as_h?
      return nil unless map_any
      map = {} of String => YAML::Any
      map_any.each do |k, v|
        name = k.as_s?
        raise SkillLoadError.new(path, "Metadata key must be a string") unless name
        map[name] = v
      end
      string_field(map, key, path)
    end
  end
end
