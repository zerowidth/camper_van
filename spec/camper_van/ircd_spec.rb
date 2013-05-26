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

    def remote_ip
      "127.0.0.1"
    end
  end

  class TestIRCD < CamperVan::IRCD
    attr_writer :campfire
    attr_writer :away
    attr_accessor :saved_channels
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

    it "only uses the subdomain if a full domain is specified" do
      @server.handle :pass => ["test.campfirenow.com:asdf1234"]
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

      context "with a JOIN command" do
        before :each do
          @server.campfire = Class.new do
            def rooms
              yield [
                OpenStruct.new(:name => "Test"),
                OpenStruct.new(:name => "Day Job")
              ]
            end
          end.new
          @connection.sent.clear
        end

        it "joins the given room" do
          @server.handle :join => ["#test"]
          @server.channels["#test"].must_be_instance_of CamperVan::Channel
        end

        it "returns an error if the room doesn't exist" do
          @server.handle :join => ["#foo"]
          @server.channels["#foo"].must_equal nil
          @connection.sent.last.must_match /no such.*room/i
        end

        it "joins multiple channels if given" do
          @server.handle :join => ["#test,#day_job"]
          @connection.sent.must_be_empty
          @server.channels["#test"].must_be_instance_of CamperVan::Channel
          @server.channels["#day_job"].must_be_instance_of CamperVan::Channel
          @ser
        end
      end

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

    context "with a QUIT command" do
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

      it "calls #part on the connected channels" do
        @channel.expect(:part, nil)
        @server.handle :quit => ["leaving..."]
      end

    end

    context "with an AWAY command" do
      before :each do
        # register
        @server.handle :pass => ["test:1234asdf"]
        @server.handle :nick => ["nathan"]
        @server.handle :user => ["nathan", 0, 0, "Nathan"]
      end

      context "with part_on_away set" do
        before :each do
          @server.options[:part_on_away] = true

          @server.campfire = Class.new do
            def rooms
              yield [
                OpenStruct.new(:name => "Test"),
                OpenStruct.new(:name => "Day Job")
              ]
            end
          end.new

          @server.handle :join => ["#test"]
          @channel = MiniTest::Mock.new
          @server.channels["#test"] = @channel

          @connection.sent.clear
        end

        after :each do
          @channel.verify
        end

        it "parts joined channels when not away" do
          @channel.expect :part, nil
          @server.away = false
          @server.handle :away => ["bbl..."]
          @server.away.must_equal true
        end

        it "rejoins previous channels when away" do
          @channel.expect :join, nil
          @server.saved_channels = ["#test"]
          @server.away = true
          @server.handle :away => []
          @server.away.must_equal false
        end
      end

      context "without part_on_away set" do
        it "calls #away while not away" do
          @server.away = false
          @server.handle :away => ["bbl..."]
          @server.away.must_equal true
          @connection.sent.last.must_equal ":nathan!nathan@127.0.0.1 306 :You have been marked as being away"
        end

        it "returns from #away while away" do
          @server.away = true
          @server.handle :away => []
          @server.away.must_equal false
          @connection.sent.last.must_equal ":nathan!nathan@127.0.0.1 305 :You are no longer marked as being away"
        end
      end
    end

  end

end

