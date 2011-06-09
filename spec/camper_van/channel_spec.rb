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
    attr_reader :locked, :full, :topic
    attr_writer :users, :topic
    def initialize
      @users = []
    end
    def locked?
      @locked
    end
    def full?
      @full
    end
    def join
      yield
    end
    def users
      yield @users if @users
    end
    def stream
      if @messages
        @messages.each { |m| yield m }
      end
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
    before :each do
    end

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

  describe "when streaming" do
    # ...
  end
end

