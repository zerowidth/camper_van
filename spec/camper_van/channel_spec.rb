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
    def subdomain
      "subdomain"
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

    def id
      10
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
      yield @users if block_given?
      @users
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
      @room.users = [
        OpenStruct.new(:id => 10, :name => "Nathan", :email_address => "x@y.com"),
        OpenStruct.new(:id => 11, :name => "Bob", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.join
      @client.sent[2].must_equal ":camper_van 353 nathan = #test :nathan bob joe"
      @client.sent[3].must_equal ":camper_van 366 nathan #test :End of /NAMES list."
    end

    it "sends the list of users including myself, even if the server doesn't say i'm there" do
      @room.users = [
        OpenStruct.new(:id => 11, :name => "Bob", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.join
      @client.sent[2].must_equal ":camper_van 353 nathan = #test :nathan bob joe"
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
    before :each do
      @room.users = [OpenStruct.new(:id => 10, :name => "Joe", :email_address => "user@example.com")]
      @channel.join
      @client.sent.clear
    end
    it "retrieves a list of users and sends them to the client" do
      @channel.list_users
      @client.sent.first.must_equal(
        ":camper_van 352 nathan #test user example.com camper_van joe H :0 Joe"
      )
      @client.sent.last.must_match /:camper_van 315 nathan #test :End/
    end

    it "issues JOIN irc commands for users who have joined but aren't yet tracked" do
      @channel.list_users
      @room.users << OpenStruct.new(:id => 11, :name => "Bob", :email_address => "bob@example.com")
      @client.sent.clear
      @channel.list_users
      @client.sent.first.must_match /bob.*JOIN #test/
    end

    it "issues PART commands for users who have left but are still tracked" do
      @room.users = []
      @channel.list_users
      @client.sent.first.must_match /joe.*PART #test/
    end

    it "shows a user as away if they are idle" do
      @channel.users[10].idle = true
      @channel.list_users
      @client.sent.first.must_match /joe G :0 Joe/
    end

    it "shows admin users as having +o" do
      @channel.users[10].admin = true
      @channel.list_users
      @client.sent.first.must_match /joe H@ :0 Joe/
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

  describe "#set_mode" do
    before :each do
      @room = OpenStruct.new :membership_limit => 10
      class << @room
        def locked?
          self.locked
        end
        def lock
          self.lock_called = true
        end
        def unlock
          self.unlock_called = true
        end
      end
      @channel = CamperVan::Channel.new("#test", @client, @room)
    end

    context "with a +i" do
      it "locks the room" do
        @channel.set_mode "+i"
        @room.lock_called.must_equal true
        @room.locked.must_equal true
      end

      it "tells the client that the channel mode has changed" do
        @channel.set_mode "+i"
        @client.sent.last.must_match /MODE #test \+ils 10/
      end
    end

    context "with a -i" do
      it "unlocks the room" do
        @channel.set_mode "-i"
        @room.unlock_called.must_equal true
        @room.locked.must_equal false
      end

      it "tells the client the channel mode has changed" do
        @channel.set_mode "-i"
        @client.sent.last.must_match /MODE #test \+ls 10/
      end
    end

    context "with an unknown mode" do
      it "replies with an irc error" do
        @channel.set_mode "+m"
        @client.sent.last.must_match /472 nathan :.*unknown mode/
      end
    end
  end

  describe "#map_message_to_irc when streaming" do
    class TestMessage < OpenStruct
      def user
        yield OpenStruct.new :name => "Joe", :id => 10, :email_address => "joe@example.com"
      end
    end

    def msg(type, attributes={})
      TestMessage.new(
        attributes.merge :type => "#{type}Message", :id => 1234
      )
    end

    it "sends a privmsg with the message when a user says something" do
      @channel.map_message_to_irc msg("Text", :body => "hello")
      @client.sent.last.must_match ":joe!joe@campfire PRIVMSG #test hello"
    end

    it "sends a privmsg with the pasted url and the first line when a user pastes something" do
      @channel.map_message_to_irc msg("Paste", :body => "foo\nbar\nbaz\nbleh")
      @client.sent.last.must_match %r(:joe\S+ PRIVMSG #test .*room/10/paste/1234)
    end

    it "sends a privmsg with an action when a user message is wrapped in *'s" do
      @channel.map_message_to_irc msg("Text", :body => "*did a thing*")
      @client.sent.last.must_match /PRIVMSG #test :\x01ACTION did a thing\x01/
    end

    it "sends an action when a user plays the crickets sound" do
      @channel.map_message_to_irc msg("Sound", :body => "crickets")
      @client.sent.last.must_match /\x01ACTION hears crickets chirping\x01/
    end

    it "sends an action when a user plays the rimshot sound" do
      @channel.map_message_to_irc msg("Sound", :body => "rimshot")
      @client.sent.last.must_match /\x01ACTION plays a rimshot\x01/
    end

    it "sends an action when a user plays the trombone sound" do
      @channel.map_message_to_irc msg("Sound", :body => "trombone")
      @client.sent.last.must_match /\x01ACTION plays a sad trombone\x01/
    end

    it "sends an action when a user plays the vuvuzela sound" do
      @channel.map_message_to_irc msg("Sound", :body => "vuvuzela")
      @client.sent.last.must_match /ACTION ======<\(\)/
    end

    it "sends an action when a user plays an unknown sound" do
      @channel.map_message_to_irc msg("Sound", :body => "boing")
      @client.sent.last.must_match /\x01ACTION played a boing sound\x01/
    end

    # it "sends a privmsg with an action when a user plays a sound"

    it "sends a mode change when the room is locked" do
      @channel.map_message_to_irc msg("Lock")
      @client.sent.last.must_match %r/:joe\S+ MODE #test \+i/
    end

    it "sends a mode change when the room is unlocked" do
      @channel.map_message_to_irc msg("Unlock")
      @client.sent.last.must_match %r/:joe\S+ MODE #test -i/
    end

    it "sends a mode change when the room disallows guests" do
      @channel.map_message_to_irc msg("DisallowGuests")
      @client.sent.last.must_match %r/:joe\S+ MODE #test \+s/
    end

    it "sends a mode change when the room allows guests" do
      @channel.map_message_to_irc msg("AllowGuests")
      @client.sent.last.must_match %r/:joe\S+ MODE #test -s/
    end

    it "sends a join command when a user enters the room" do
      @channel.map_message_to_irc msg("Enter")
      @client.sent.last.must_match %r/:joe\S+ JOIN #test/
    end

    it "adds the user to the internal tracking list when a user joins" do
      @channel.map_message_to_irc msg("Enter")
      @client.sent.last.must_match %r/:joe\S+ JOIN #test/
      @channel.users[10].wont_equal nil
    end

    it "sends a part command when a user leaves the room" do
      @channel.map_message_to_irc msg("Leave")
      @client.sent.last.must_match %r/:joe\S+ PART #test/
    end

    it "removes the user from the tracking list when they depart" do
      @channel.map_message_to_irc msg("Enter")
      @channel.map_message_to_irc msg("Leave")
      @channel.users.size.must_equal 0
    end

    it "sends a part command when a user is kicked from the room" do
      @channel.map_message_to_irc msg("Kick")
      @client.sent.last.must_match %r/:joe\S+ PART #test/
    end

    # it "sends the tweet url when a user pastes a tweet"

    it "sends a topic command when a user changes the topic" do
      @channel.map_message_to_irc msg("TopicChange", :body => "new topic")
      @client.sent.last.must_match ":joe!joe@campfire TOPIC #test :new topic"
    end

    it "sends a message containing the upload link when a user uploads a file" do
      @channel.map_message_to_irc msg("Upload", :body => "filename")
      @client.sent.last.must_match %r(:joe\S+ PRIVMSG #test .*uploads/1234/filename)
    end

    # it "sends a notice with the message when the system sends a message"

    it "marks the user as away when a user goes idle" do
      @channel.map_message_to_irc msg("Enter")
      @channel.map_message_to_irc msg("Idle")
      @channel.users[10].idle?.must_equal true
    end

    it "marks the user as back when a user becomes active" do
      @channel.map_message_to_irc msg("Enter")
      @channel.map_message_to_irc msg("Idle")
      @channel.map_message_to_irc msg("Unidle")
      @channel.users[10].idle?.must_equal false
    end
  end
end

