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

  def self.reset
    @@count = 0
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

  def self.reset
    @@count = 0
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
  before_each do
    Main.reset
    Child.reset
  end

  it "should be able to spawn actors" do
    system = Movie::ActorSystem(MainMessage).new(Main.create())

    system << MainMessage.new(message: "hello")
    sleep(0.05)
    Main.count.should eq(1)

    main = system.spawn(Main.create())

    child = system.spawn(Child.create(main))
    child << "message "
    sleep(0.001)
    Child.count.should eq(1)
    Main.count.should eq(2)
  end

  it "invokes Behaviors.receive handler and returns behavior" do
    handler_called = false
    returned_behavior : Movie::AbstractBehavior(String)? = nil

    receive_behavior = Movie::Behaviors(String).receive do |message, context|
      handler_called = true
      behavior = Movie::Behaviors(String).stopped
      returned_behavior = behavior
      behavior
    end

    system = Movie::ActorSystem(String).new(Movie::Behaviors(String).same)
    actor = system.spawn(receive_behavior)

    actor << "ping"
    sleep(0.05)

    handler_called.should be_true
    returned_behavior.should_not be_nil
    returned_behavior.not_nil!.should be_a(Movie::AbstractBehavior(String))
  end

  it "exposes context log" do
    logger : Log? = nil

    behavior = Movie::Behaviors(String).receive do |message, context|
      logger = context.log
      Movie::Behaviors(String).same
    end

    system = Movie::ActorSystem(String).new(Movie::Behaviors(String).same)
    actor = system.spawn(behavior)

    actor << "ping"
    sleep(0.05)

    logger.should_not be_nil
    logger.not_nil!.responds_to?(:debug).should be_true
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
