require "athena-dotenv"

module Agency
  module EnvLoader
    def self.load(path : String = ".env") : Hash(String, String)
      return {} of String => String unless File.exists?(path)

      dotenv = Athena::Dotenv.new
      data = normalize_exports(File.read(path))
      values = dotenv.parse(data, path)
      dotenv.populate(values)
      values
    end

    private def self.normalize_exports(data : String) : String
      data.gsub(Regex.new("^\\s*export\\s+", Regex::Options::MULTILINE), "")
    end
  end
end
