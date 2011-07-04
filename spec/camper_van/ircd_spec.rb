require "spec_helper"

describe CamperVan::IRCD do
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

  class TestIRCD < CamperVan::IRCD
    attr_writer :campfire
  end

  before :each do
    @connection = TestConnection.new
    @server = TestIRCD.new(@connection)

    @server.campfire = Class.new do
      def user(*args)
        yield OpenStruct.new(:name => "Nathan")
      end
    end.new
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

    it "forces a nick change to match the campfire user if it doesn't match" do
      @server.handle :pass => ["test:1234asdf"]
      @server.handle :nick => ["bob"]
      @server.handle :user => ["nathan", 0, 0, "Nathan"]
      line = @connection.sent.detect { |c| c =~ /NICK/ }
      line.must_match /NICK nathan/
    end

    it "returns an error and shuts down if campfire can't be contacted" do
      @server.campfire = Class.new do
        def user(*args)
          raise Firering::Connection::HTTPError,
            OpenStruct.new(:error => "could not connect")
        end
      end.new
      @server.handle :pass => ["test:1234asdf"]
      @server.handle :nick => ["bob"]
      @server.handle :user => ["nathan", 0, 0, "Nathan"]
      @connection.sent.last.must_match /NOTICE .*could not connect/
    end

    it "returns an error if the campfire api key is incorrect (user info is nil)" do
      @server.campfire = Class.new do
        def user(*args)
          yield OpenStruct.new # nil everything
        end
      end.new
      @server.handle :pass => ["test:1234asdf"]
      @server.handle :nick => ["bob"]
      @server.handle :user => ["nathan", 0, 0, "Nathan"]
      @connection.sent.last.must_match /NOTICE .*invalid api key/i
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
        @channel = MiniTest::Mock.new

        # register
        @server.handle :pass => ["test:1234asdf"]
        @server.handle :nick => ["nathan"]
        @server.handle :user => ["nathan", 0, 0, "Nathan"]

        @server.channels["#test"] = @channel
      end

      after :each do
        @channel.verify
      end

      it "asks the channel to send its mode" do
        @channel.expect :current_mode, nil
        @server.handle :mode => ["#test"]
      end

      it "with a +i sets the channel mode to +i" do
        @channel.expect :set_mode, nil, ["+i"]
        @server.handle :mode => ["#test", "+i"]
      end

      it "with a -i sets the channel mode to -i" do
        @channel.expect :set_mode, nil, ["-i"]
        @server.handle :mode => ["#test", "-i"]
      end

      context "with an unknown mode argument" do
        it "responds with an error" do
          @server.handle :mode => ["#test", "-t"]
          @connection.sent.last.must_match /472 nathan t :Unknown mode t/
        end
      end

    end

    context "with a WHO command" do
      before :each do
        @channel = MiniTest::Mock.new

        # register
        @server.handle :pass => ["test:1234asdf"]
        @server.handle :nick => ["nathan"]
        @server.handle :user => ["nathan", 0, 0, "Nathan"]

        @server.channels["#test"] = @channel
      end

      after :each do
        @channel.verify
      end

      it "asks campfire for a list of users" do
        @channel.expect(:list_users, nil)
        @server.handle :who => ["#test"]
      end

      it "returns 'end of list' only when an invalid channel is specified" do
        @server.handle :who => ["#invalid"]
        @connection.sent.last.must_match /^:camper_van 315 nathan #invalid :End/
      end
    end

  end

end

