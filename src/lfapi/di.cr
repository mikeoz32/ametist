module LF::DI
  private SERVICE_CLASSES = {} of String => Nil
  macro finished
    # Macro that searches for services and creates ApplicationConfig implementation
    # with factories for services,
    # eg for service
    # ```crystal
    # @[LF::DI::Service]
    # class S
    #   def initialize
    #     puts "S initialized"
    #   end
    # end
    # ```
    # macro will add method to configuration
    # ```crystal
    # @[LF::DI::Bean]
    # def create_s
    #   S.new
    # end
    # ```
    #
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

  annotation Bean
    # Marks class method as a bean factory method
    # Parameters:
    #   name: String - The name of the bean
    #   scope: String - The scope of the bean (singleton, prototype, etc.)
  end

  module BeanFactory
  end

  class BeanFactoryImpl(T)
    include BeanFactory
    def initialize (*, name : String, scope : String = "singleton", @factory : Proc(ApplicationContext, T))
      @name = name
      @scope = scope
    end

    def create(context : ApplicationContext) : T
      @factory.call(context)
    end
  end

  module ApplicationContext
    # ApplicationContext interface
    # Should be included in implementations
  end

  module ApplicationConfig
    # ApplicationConfig interface
    # Should be included in implementations

    macro included
      macro finished
        {% verbatim do %}
          {%
            @type.methods.each do |method|
              method.annotations(LF::DI::Bean).each do |ann|
                puts "Found bean method: #{method.body}"
                raise "Bean name is required" unless ann.named_args.has_key?("name")
                puts "Bean name: #{ann["name"]}"
                bean_name = ann["name"]
              end
            end
          %}
        {% end %}
      end
    end
  end

  abstract class AbstractApplicationContext
    include ApplicationContext

    @configurations : Set(ApplicationConfig) = Set(ApplicationConfig).new
    @factories = Hash(String, BeanFactory).new

    def register(config : ApplicationConfig)
      @configurations.add(config)
    end

    def add_bean(*, name : String, scope : String = "singleton", type : T.class, &factory : Proc(ApplicationContext, T)) forall T
      @factories[name] = BeanFactoryImpl(T).new(name: name, scope: scope, factory: factory).as(BeanFactory)
    end

    def get_bean(name : String, type : T.class) : T forall T
      raise "No bean found" unless @factories.has_key?(name)
      @factories[name].as(BeanFactoryImpl(T)).create(self)
    end

    delegate has_key?, to: @factories
  end

  class AnnotationApplicationContext < AbstractApplicationContext
  end

end

# Pass tuple as arguments to a function
# def test1(a : String, b : Int32)
#   puts "test1 called"
# end

# t = {"test", 1}

# test1(*t)
