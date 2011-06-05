require "spec_helper"

describe CamperVan::CommandDefinition do
  before :each do
    @test_commands = Class.new do
      include CamperVan::CommandDefinition
      attr_accessor :nick

      handle :nick do |args|
        @nick = args.first
        args
      end

    end
  end

  it "defines a handle class method on a class" do
    @test_commands.must_respond_to :handle
  end

  it "defines a handle instance method on a class" do
    @test_commands.new.must_respond_to :handle
  end

  describe "#handle" do
    before :each do
      @cmd = @test_commands.new
    end

    it "raises an exception when no handler is available" do
      lambda { @cmd.handle(:foo => []) }.must_raise(CamperVan::HandlerMissing)
    end

    it "passes the arguments to the block" do
      @cmd.handle(:nick => %w(lol what)).must_equal %w(lol what)
    end

    it "evaluates the block in the instance context" do
      @cmd.nick.must_equal nil
      @cmd.handle(:nick => ["bob"])
      @cmd.nick.must_equal "bob"
    end
  end

  describe ".handle" do
    it "defines a handler for the given command" do
      @test_commands.handle :foo do
        "success"
      end
      @test_commands.new.handle(:foo => []).must_equal "success"
    end
  end

end
