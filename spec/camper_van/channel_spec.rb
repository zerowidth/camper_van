require "spec_helper"

describe CamperVan::Channel do

  class TestClient
    attr_reader :sent, :nick, :user, :host
    include CamperVan::ServerReply
    def initialize
      @nick, @user, @host = "nathan", "nathan", "localhost"
      @sent = []
    end
    def send_line(line)
      @sent << line
    end
  end

  class TestRoom
    attr_reader :locked, :full, :topic, :membership_limit
    attr_reader :sent

    attr_writer :users, :topic, :locked, :full, :open_to_guests
    attr_writer :stream

    def initialize
      @users = []
      @sent = []
      @membership_limit = 12
    end
    def locked?
      @locked
    end
    def full?
      @full
    end
    def open_to_guests?
      @open_to_guests
    end
    def join
      yield
    end
    def users
      yield @users if @users
    end

    def text(line)
      @sent << line
    end

    def stream
      if @messages
        @messages.each { |m| yield m }
      end
      return @stream
    end
  end

  User = Struct.new(:name)

  before :each do
    @client = TestClient.new
    @room = TestRoom.new
    @room.topic = "the topic"
    @channel = CamperVan::Channel.new("#test", @client, @room)
  end

  describe "#join" do
    it "sends a user join as the command" do
      @channel.join
      @client.sent.first.must_equal ":nathan!nathan@localhost JOIN :#test"
    end

    it "sends the topic as a command" do
      @channel.join
      @client.sent[1].must_equal ":camper_van 332 nathan #test :the topic"
    end

    it "sends the list of users" do
      @room.users = [User.new("nathan"), User.new("bob"), User.new("joe")]
      @channel.join
      @client.sent[2].must_equal ":camper_van 353 nathan = #test :nathan bob joe"
      @client.sent[3].must_equal ":camper_van 366 nathan #test :End of /NAMES list."
    end
  end

  describe "#part" do
    it "sends a part command to the client" do
      @channel.part
      @client.sent.last.must_match /PART #test/
    end

    it "closes the connection on the stream" do
      @room.stream = MiniTest::Mock.new
      @room.stream.expect(:close_connection, nil)
      @channel.stream_campfire_to_channel # sets up stream
      @channel.part

      @room.stream.verify
    end
  end

  describe "#list_users" do
    it "retrieves a list of users and sends them to the client" do
      @room.users = [OpenStruct.new(:name => "Joe", :email_address => "user@example.com")]
      @channel.list_users
      @client.sent.first.must_equal(
        ":camper_van 352 nathan #test user example.com camper_van joe H :0 Joe"
      )
      @client.sent.last.must_match /:camper_van 315 nathan #test :End/
    end
  end

  describe "#privmsg" do
    it "sends the message as text to the room" do
      @channel.privmsg "hello world"
      @room.sent.first.must_equal "hello world"
    end

    it "converts ACTION messages to campfire-appropriate messages" do
      @channel.privmsg "\01ACTION runs away\01"
      @room.sent.first.must_equal "*runs away*"
    end
  end

  describe "#current_mode" do
    it "sends the current mode to the client" do
      @channel.current_mode
      @client.sent.last.must_match ":camper_van 324 nathan #test +ls 12"
    end

    context "and a locked room" do
      it "includes +i mode" do
        @room.locked = true
        @channel.current_mode
        @client.sent.last.must_match ":camper_van 324 nathan #test +ils 12"
      end
    end

    context "and a room that allows guests" do
      it "drops the +s from the mode" do
        @room.open_to_guests = true
        @channel.current_mode
        @client.sent.last.must_match ":camper_van 324 nathan #test +l 12"
      end
    end
  end

  describe "when streaming" do
    # ...
  end
end

