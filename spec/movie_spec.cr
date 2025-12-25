require "../src/movie"
require "./spec_helper"

class Main < Movie::AbstractBehavior(MainMessage)
  @@count : Int32 = 0
  def self.create()
    new()
  end

  def self.count
    @@count
  end

  def receive(message, context)
    puts message.message + " " + @@count.to_s
    @@count += 1
  end
end

class Child < Movie::AbstractBehavior(String)
  @parent : Movie::ActorRef(MainMessage)

  @@count : Int32 = 0

  def self.count
    @@count
  end

  def self.create(parent)
    new(parent)
  end

  protected def initialize(parent)
    @parent = parent
  end

  def receive(message, context)
    @@count += 1
    @parent << MainMessage.new(message: message)
  end
end



describe Movie do
  it "should be able to spawn actors" do
    system = Movie::ActorSystem(MainMessage).new(Main.create())
    main = system.spawn(Main.create())

    child = system.spawn(Child.create(main))
    child << "message "
    sleep(0.001)
    Child.count.should eq(1)
    Main.count.should eq(1)
  end

  it "Should handle exception" do
    system = Movie::ActorSystem(MainMessage).new(Main.create())
    ref = system.spawn (Movie::Behaviors(String).setup do |context|
      Movie::Behaviors(String).receive do |message, context|
        puts "Functional message #{message}"
        puts "context #{context}"
        raise "Should be handled"
        Movie::Behaviors(String).same
      end
    end)
    ref << "message "
    sleep(10)
  end


end
