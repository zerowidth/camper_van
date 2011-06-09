require "spec_helper"

describe CamperVan::CampfireServer do
  class TestConnection
    attr_reader :sent

    def initialize
      @sent = []
    end

    def send_line(line)
      @sent << line
    end

    def close_connection
    end

    def get_peername
      "xx" + [6667, 127, 0, 0, 1].pack("nC4")
    end
  end

  before :each do
    @connection = TestConnection.new
    @server = CamperVan::CampfireServer.new(@connection)
  end

  describe "#handle" do
    it "saves the subdomain and API key from the PASS command" do
      @server.handle :pass => ["test:asdf1234"]
      @server.subdomain.must_equal "test"
      @server.api_key.must_equal "asdf1234"
    end

    it "saves the nickname from the NICK command" do
      @server.handle :nick => ["nathan"]
      @server.nick.must_equal "nathan"
    end

    it "saves the user and host from the USER command" do
      @server.handle :user => ["nathan", 0, 0, "Nathan"]
      @server.user.must_equal "nathan"
      @server.host.must_equal "127.0.0.1"
    end

    it "responds with an error when given a nick and user without a password" do
      @server.handle :nick => ["nathan"]
      @server.handle :user => ["nathan", 0, 0, "Nathan"]
      @connection.sent.first.must_match /^:camper_van NOTICE AUTH :.*password/
    end

    it "responds with welcome messages after receiving a valid registration" do
      @server.handle :pass => ["test:1234asdf"]
      @server.handle :nick => ["nathan"]
      @server.handle :user => ["nathan", 0, 0, "Nathan"]
      @connection.sent.first.must_match /^:camper_van 001 nathan/
    end

    context "when registered" do
      before :each do
        @server.handle :pass => ["test:1234asdf"]
        @server.handle :nick => ["nathan"]
        @server.handle :user => ["nathan", 0, 0, "Nathan"]
      end

      # it "connects to the campfire API" do
      #   skip "campfire api next!"
      # end
    end

    context "with a MODE command" do

      before :each do
        @campfire = MiniTest::Mock.new

        # register
        @server.handle :pass => ["test:1234asdf"]
        @server.handle :nick => ["nathan"]
        @server.handle :user => ["nathan", 0, 0, "Nathan"]

        @server.active_channels["#test"] = @campfire
      end

      after :each do
        @campfire.verify
      end

      it "asks the channel to send its mode" do
        @campfire.expect :current_mode, nil
        @server.handle :mode => ["#test"]
      end

    end

    context "with a WHO command" do
      before :each do
        @campfire = MiniTest::Mock.new

        # register
        @server.handle :pass => ["test:1234asdf"]
        @server.handle :nick => ["nathan"]
        @server.handle :user => ["nathan", 0, 0, "Nathan"]

        @server.active_channels["#test"] = @campfire
      end

      after :each do
        @campfire.verify
      end

      it "asks campfire for a list of users" do
        @campfire.expect(:list_users, nil)
        @server.handle :who => ["#test"]
      end

      it "returns 'end of list' only when an invalid channel is specified" do
        @server.handle :who => ["#invalid"]
        @connection.sent.last.must_match /^:camper_van 315 nathan #invalid :End/
      end
    end

  end

end

