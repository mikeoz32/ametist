require "json"

module Agency
  module SchemaValidator
    def self.validate(schema : JSON::Any, args : JSON::Any) : Array(String)
      errors = [] of String
      type = schema["type"]?.try(&.as_s?) || "object"
      case type
      when "object"
        unless args.as_h?
          errors << "Expected object arguments"
          return errors
        end
        props = schema["properties"]?.try(&.as_h?) || {} of String => JSON::Any
        required = [] of String
        if req_node = schema["required"]?
          if req_arr = req_node.as_a?
            required = req_arr.map(&.as_s)
          end
        end
        required.each do |name|
          errors << "Missing required field: #{name}" unless args.as_h.has_key?(name)
        end
        props.each do |name, spec|
          next unless args.as_h.has_key?(name)
          unless type_matches?(spec, args.as_h[name])
            expected = spec["type"]?.try(&.as_s?) || "unknown"
            errors << "Invalid type for #{name}: expected #{expected}"
          end
        end
      else
        errors << "Unsupported schema type: #{type}"
      end
      errors
    end

    private def self.type_matches?(spec : JSON::Any, value : JSON::Any) : Bool
      expected = spec["type"]?.try(&.as_s?) || "object"
      case expected
      when "string" then value.as_s? != nil
      when "number" then value.as_f? != nil
      when "integer" then value.as_i? != nil
      when "boolean" then value.as_bool? != nil
      when "array" then value.as_a? != nil
      when "object" then value.as_h? != nil
      else
        true
      end
    end
  end
end
