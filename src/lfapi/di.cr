module LF::DI
  private SERVICE_CLASSES = {} of String => Nil
  macro finished
    {%
      services = [] of Nil

      Object.all_subclasses.each do |klass|
        klass.annotations(LF::DI::Service).each do |ann|
          puts "Found annotation: #{ann.name} for #{klass.name}"
          services << klass
        end
      end

      puts services
      services.each do |service|
        SERVICE_CLASSES[service.name] = service
      end
      puts "Finished service discovery"
    %}
  end

  annotation Service
  end


  class Container
    def initialize
    {% begin %}
      {% for key, value in SERVICE_CLASSES %}
        puts {{ value }}
      {% end %}
    {% end %}
    end
  end
end
