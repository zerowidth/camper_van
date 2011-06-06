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
      @server.sent.first.must_equal ":camper_van 001 nathan :welcome"
    end
  end

  describe "#command_reply" do
    it "replies with the given command and arguments" do
      @server.command_reply :notice, "nickname", "hello there"
      @server.sent.first.must_equal ":camper_van NOTICE nickname :hello there"
    end

    it "does not prefix strings with a : if they have one already" do
      @server.command_reply :notice, "nickname", ":hello there"
      @server.sent.first.must_equal ":camper_van NOTICE nickname :hello there"
    end
  end
end
