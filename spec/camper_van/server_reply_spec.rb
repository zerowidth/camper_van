require "spec_helper"

describe CamperVan::ServerReply do
  before :each do
    @test_server = Class.new do
      include CamperVan::ServerReply

      attr_reader :sent, :nick, :user, :host
      def initialize
        @sent = []
        @nick, @user, @host = %w(nathan nathan localhost)
      end
      def send_line(data)
        @sent << data
      end

    end

    @server = @test_server.new
  end

  describe "#numeric_reply" do
    it "sends the coded command from the server" do
      @server.numeric_reply(:rpl_welcome, ":welcome")
      @server.sent.size.must_equal 1
      @server.sent.first.must_equal ":camper_van 001 nathan :welcome"
    end
  end

  describe "#command_reply" do
    it "replies with the given command and arguments" do
      @server.command_reply :notice, "nickname", "hello there"
      @server.sent.size.must_equal 1
      @server.sent.first.must_equal ":camper_van NOTICE nickname :hello there"
    end

    it "does not prefix strings with a : if they have one already" do
      @server.command_reply :notice, "nickname", ":hello there"
      @server.sent.size.must_equal 1
      @server.sent.first.must_equal ":camper_van NOTICE nickname :hello there"
    end
  end

  describe "#user_reply" do
    it "replies with the given command directed to the user" do
      @server.user_reply :join, "#chan"
      @server.sent.size.must_equal 1
      @server.sent.first.must_equal ":nathan!nathan@localhost JOIN #chan"
    end

    it "prefixes the final argument with : if it has spaces" do
      @server.user_reply :privmsg, "#chan", "hello world"
      @server.sent.size.must_equal 1
      @server.sent.first.must_equal ":nathan!nathan@localhost PRIVMSG #chan :hello world"
    end
  end

  describe "#campfire_reply" do
    it "replies with a command from the given nickname" do
      @server.campfire_reply :privmsg, "joe", "#chan", "hello world"
      @server.sent.size.must_equal 1
      @server.sent.first.must_equal ":joe!joe@campfire PRIVMSG #chan :hello world"
    end
  end

end
