require "spec_helper"

describe CamperVan::Channel do

  class TestClient
    attr_reader :sent, :nick, :user, :host
    attr_writer :nick
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
    attr_reader :stream_count
    attr_reader :left

    attr_writer :users, :topic, :locked, :full, :open_to_guests
    attr_writer :stream

    attr_accessor :connection

    def initialize
      @users = []
      @sent = []
      @membership_limit = 12
      @stream_count = 0
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

    def leave
      @left = true
    end

    def users
      yield @users if block_given?
      @users
    end

    def text(line)
      @sent << line
    end

    def tweet(line)
      @sent << [:tweet, line]
    end

    def stream
      @stream_count += 1
      if @messages
        @messages.each { |m| yield m }
      end
      @stream ||= "message stream" # must be truthy
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

    it "sends the topic as a command even if the topic is nil" do
      @room.topic = nil
      @channel.join
      @client.sent[1].must_equal ":camper_van 332 nathan #test :"
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

    it "does not stream messages from the room on a second join" do
      @channel.join
      @channel.join
      @room.stream_count.must_equal 1
    end

    it "returns an error if the room is locked" do
      @room.locked = true
      @channel.join
      @client.sent.last.must_match /Cannot join #test.*locked/
    end

    it "returns an error if the room is full" do
      @room.full = true
      @channel.join
      @client.sent.last.must_match /Cannot join #test.*full/
    end
  end

  describe "#part" do
    it "sends a part command to the client" do
      @channel.part
      @client.sent.last.must_match /PART #test/
    end

    it "closes the connection on the stream" do
      stream = Class.new do
        attr_reader :closed
        def close_connection
          @closed = true
        end
      end

      @room.stream = stream.new
      @channel.stream_campfire_to_channel # sets up stream
      @channel.part

      assert @room.stream.closed
    end

    it "closes the em-http connection if present" do
      stream = Class.new do
        attr_reader :closed
        def close # em-http defines this
          @closed = true
        end
      end

      @room.stream = stream.new
      @channel.stream_campfire_to_channel # sets up stream
      @channel.part

      assert @room.stream.closed
    end

    it "leaves the channel" do
      @channel.part
      assert @room.left
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

    it "converts twitter urls to tweet messages" do
      url = "https://twitter.com/aniero/status/12345"
      @channel.privmsg url
      @room.sent.first.must_equal [:tweet, url]
    end

    it "converts leading nicknames into campfire names" do
      # get the users into the room
      @room.users = [
        OpenStruct.new(:id => 11, :name => "Bob Fred", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users

      @channel.privmsg "bob_fred: sup dude"
      @room.sent.last.must_match /Bob Fred: sup dude/
    end

    it "converts names on any part" do
      @room.users = [
        OpenStruct.new(:id => 11, :name => "JD Wolk", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users

      @channel.privmsg "sup dude jd_wolk"
      @room.sent.last.must_match /sup dude JD Wolk/
    end

    it "converts various nicknames" do
      @room.users = [
        OpenStruct.new(:id => 11, :name => "JD Wolk", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Pedro Nascimento", :email_address => "x@y.com"),
        OpenStruct.new(:id => 13, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users

      @channel.privmsg "sup dude jd_wolk and pedro_nascimento!"
      @room.sent.last.must_match /sup dude JD Wolk and Pedro Nascimento!/

    end

    it "converts leading nicknames followed by punctuation" do
      @room.users = [
        OpenStruct.new(:id => 11, :name => "Bob Fred", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users

      @channel.privmsg "bob_fred! sup!"
      @room.sent.last.must_match /Bob Fred! sup/
    end

    it "converts just leading nicks to names" do
      @room.users = [
        OpenStruct.new(:id => 11, :name => "Bob Fred", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users

      @channel.privmsg "bob_fred"
      @room.sent.last.must_match /Bob Fred/
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

    it "skips text messages from the current user" do
      @client.nick = "joe"
      @channel.map_message_to_irc msg("Text", :body => "hello", :user_id => 10)
      @client.sent.last.must_equal nil
    end

    it "sends a privmsg with the message when a user says something" do
      @channel.map_message_to_irc msg("Text", :body => "hello there")
      @client.sent.last.must_match ":joe!joe@campfire PRIVMSG #test :hello there"
    end

    it "splits text messages on newline and carriage returns" do
      @channel.map_message_to_irc msg("Text", :body => "hello\n\r\r\nthere")
      @client.sent[-2].must_match ":joe!joe@campfire PRIVMSG #test :hello"
      @client.sent[-1].must_match ":joe!joe@campfire PRIVMSG #test :there"
    end

    it "sends the first few lines, split by newline or carriage return, for a paste" do
      @channel.map_message_to_irc msg("Paste", :body => "foo\r\nbar\nbaz\nbleh")
      @client.sent[-4].must_match %r(:joe\S+ PRIVMSG #test :> foo)
      @client.sent.last.must_match %r(:joe\S+ PRIVMSG #test .*room/10/paste/1234)
    end

    it "sends a privmsg with the pasted url and the first line when a user pastes something" do
      @channel.map_message_to_irc msg("Paste", :body => "foo\nbar\nbaz\nbleh")
      @client.sent.last.must_match %r(:joe\S+ PRIVMSG #test .*room/10/paste/1234)
    end

    it "sends a privmsg with an action when a user message is wrapped in *'s" do
      @channel.map_message_to_irc msg("Text", :body => "*did a thing*")
      @client.sent.last.must_match /PRIVMSG #test :\x01ACTION did a thing\x01/
    end

    it "converts leading name matches to irc nicks" do
      # get the users into the room
      @room.users = [
        OpenStruct.new(:id => 11, :name => "Bob Fred", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users
      @client.sent.clear

      # now check the mapping
      @channel.map_message_to_irc msg("Text", :body => "Bob Fred: hello")
      @client.sent.last.must_match %r(PRIVMSG #test :bob_fred: hello)
    end

    it "converts just leading names to nicks" do
      @room.users = [
        OpenStruct.new(:id => 11, :name => "Bob Fred", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users
      @channel.map_message_to_irc msg("Text", :body => "Bob Fred")
      @client.sent.last.must_match %r(PRIVMSG #test :bob_fred)
    end

    it "converts leading names plus punctuation to nicks" do
      @room.users = [
        OpenStruct.new(:id => 11, :name => "Bob Fred", :email_address => "x@y.com"),
        OpenStruct.new(:id => 12, :name => "Joe", :email_address => "x@y.com")
      ]
      @channel.list_users

      @channel.map_message_to_irc msg("Text", :body => "Bob Fred!!? dude!")
      @client.sent.last.must_match %r(PRIVMSG #test :bob_fred!!\? dude)
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

    it "does not resend a join command when a user enters the room twice" do
      @channel.map_message_to_irc msg("Enter")
      @client.sent.clear
      @client.sent.last.must_equal nil
      @channel.map_message_to_irc msg("Enter")
      @client.sent.last.must_equal nil
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

    it "sends a topic command when a user changes the topic" do
      @channel.map_message_to_irc msg("TopicChange", :body => "new topic")
      @client.sent.last.must_match ":joe!joe@campfire TOPIC #test :new topic"
    end

    it "sends a message containing the upload link when a user uploads a file" do
      conn = Class.new do
        def http(method, url)
          raise "bad method #{method}" unless method == :get
          raise "bad url #{url}" unless url == "/room/456/messages/1234/upload.json"
          yield :upload => {:full_url => "filename"}
        end
      end.new
      @room.connection = conn
      @channel.map_message_to_irc msg("Upload", :body => "filename", :room_id => 456)
      @client.sent.last.must_match %r(:joe\S+ PRIVMSG #test .* filename)
    end

    it "sends a message containing the tweet url when a user posts a tweet" do
      body = "hello world -- @author, twitter.com/aniero/status/12345.*"
      @channel.map_message_to_irc msg("Tweet", :body => body)
      @client.sent.last.must_match %r(:joe\S+ PRIVMSG #test .*twitter.com/aniero/status/12345.*)
    end

    it "splits on newline or carriage returns in tweets" do
      body = "hello world\nsays me -- @author, twitter.com/aniero/status/12345.*"
      @channel.map_message_to_irc msg("Tweet", :body => body)
      @client.sent[-2].must_match %r(:joe\S+ PRIVMSG #test :hello world)
      @client.sent.last.must_match %r(:joe\S+ PRIVMSG #test :says.*twitter.com/aniero/status/12345.*)
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

