require "socket" # for gethostname

module CamperVan

  # the IRCD is the server that IRC clients connect to. It handles:
  #
  # * irc client registration and validation against campfire
  # * mapping irc commands to internal Commands
  # * proxying irc commands to campfire channels
  class IRCD

    # The IRC client
    attr_reader :client

    # Registration information for campfire authentication,
    # comes from the PASS command from the irc client
    attr_reader :subdomain, :api_key

    # Information for the connected user
    attr_reader :nick, :user, :host

    # A Hash of connected CampfireChannels
    attr_reader :channels

    # Whether or not this server is actively sending/receiving data.
    # Set to false when shutting down so extra commands are ignored.
    attr_reader :active

    MOTD = <<-motd
      Welcome to CamperVan.
      To see what campfire rooms are available to the
      configured subdomain and api key, use the LIST command.
    motd

    include CommandDefinition # handle :command { ... }
    include CommandParser     # parses IRC commands
    include ServerReply       # IRC reply helpers
    include Utils             # irc translation helpers
    include Logger            # logging helper

    # Public: initialize an IRC server connection
    #
    # client - the EM connection representing the IRC client
    def initialize(client)
      @client = client
      @active = true
      @channels = {}
    end

    # The campfire client
    #
    # Returns the existing or initializes a new instance of a campfire
    # client using the configured subdomain and API key.
    def campfire
      @campfire ||= Firering::Connection.new(
        "https://#{subdomain}.campfirenow.com"
      ) do |c|
        c.token = api_key
        c.logger = CamperVan.logger
      end
    end

    # Handler for when a client sends an IRC command
    def receive_line(line)
      if @active
        cmd = parse(line)
        handle cmd
      end
    rescue HandlerMissing
      logger.info "ignoring irc command #{cmd.inspect}: no handler"
    end

    # Send a line back to the irc client
    def send_line(line)
      client.send_line line if @active
    end

    # Shuts down this connection to the server
    def shutdown
      @active = false
      client.close_connection
    end

    # IRC registration sequence:
    #
    #   PASS <password> (may not be sent!)
    #   NICK <nickname>
    #   USER <user info>
    #

    # PASS command handler
    handle :pass do |args|
      if args.empty?
        numeric_reply :err_needmoreparams, ":must specify a password: subdomain:api_key"
        shutdown
      else
        @subdomain, @api_key = *args.first.split(":")
      end
    end

    # NICK command handler
    #
    # As a part of the registration sequence, sets the nickname.
    # If sent after the client is registered, responds with an IRC
    # error, as nick changes with campfire are disallowed (TODO)
    handle :nick do |args|
      if args.empty?
        numeric_reply :err_nonicknamegiven, ":no nickname given"
      else
        if @nick
          # TODO error
        else
          @nick = args.first
        end
      end
    end

    # USER command handler
    #
    # Final part of the registration sequence.
    # If registration is successful, sends a welcome reply sequence.
    handle :user do |args|
      if args.size < 4
        numeric_reply :err_needmoreparams, "Need more params"
      else
        @user = args.first
        # grab the remote IP address for the client
        @host = client.remote_ip

        unless @api_key
          command_reply :notice, "AUTH", "*** must specify campfire API key as password ***"
          shutdown
          return
        end

        successful_registration
      end
    end

    # PING command handler.
    #
    # Responds with a PONG
    handle :ping do |args|
      command_reply :pong, *args
    end

    # LIST command handler
    #
    # Sends the list of available campfire channels to the client.
    handle :list do |args|
      # hooray async code: have to do gymnastics to make this appear
      # sequential
      campfire.rooms do |rooms|
        sent = 0
        rooms.each do |room|
          name = "#" + irc_name(room.name)
          topic = room.topic
          room.users do |users|
            numeric_reply :rpl_list, name, users.size, topic
            sent += 1
            if sent == rooms.size
              numeric_reply :rpl_listend, "End of list"
            end
          end
        end
      end
    end

    handle :who do |args|
      if channel = channels[args.first]
        channel.list_users
      else
        if args.empty?
          numeric_reply :rpl_endofwho, "End of WHO list"
        else
          numeric_reply :rpl_endofwho, args.first, "End of WHO list"
        end
      end
    end

    handle :join do |args|
      args = args.map { |args| args.split(",")}.flatten
      args.each do |channel|
        join_channel channel
      end
    end

    handle :part do |args|
      name = args.first
      # FIXME parting a channel should remove the channel from channels, except
      # that there's a bug with EM that won't disconnect the streaming request.
      # Because of that, leave the channel in the list, and assume the irc
      # client attached to this IRCD will ignore messages from channels it's not
      # currently in.
      if channel = channels[name]
        channel.part
      else
        numeric_reply :err_notonchannel, "You're not on that channel"
      end
    end

    handle :topic do |args|
      name, new_topic = *args
      if channel = channels[name]
        if new_topic
          channel.set_topic new_topic
        else
          channel.current_topic
        end
      else
        # TODO topic error
      end
    end

    handle :privmsg do |args|
      name, msg = *args
      if channel = channels[name]
        channel.privmsg msg
      else
        numeric_reply :err_nonicknamegiven, name, "No such nick/channel"
      end
    end

    handle :mode do |args|
      if channel = channels[args.shift]

        if mode = args.first
          if mode =~ /^[+-][si]$/
            channel.set_mode mode
          else
            mode = mode.gsub(/\W/,'')
            numeric_reply :err_unknownmode, mode, "Unknown mode #{mode}"
          end
        else
          channel.current_mode
        end

      else
        # no error message for this situation, so ignore it silently
      end
    end

    handle :away do |args|
      # ignore silently, there's no campfire API for this
    end

    handle :quit do |args|
      channels.values.each do |channel|
        channel.part
      end
      shutdown
    end

    # Completes a successful registration with the appropriate responses
    def successful_registration
      check_campfire_authentication do
        check_nick_matches_authenticated_user
        send_welcome
        send_luser_info
        send_motd
      end
    end

    # Checks that the campfire authentication is successful.
    #
    # callback - a block to call if successful.
    #
    # Yields to the callback on success (async)
    #
    # If it fails, it replies with an error to the client and
    # disconnects.
    def check_campfire_authentication(&callback)
      # invalid user only returns a nil result!
      campfire.user("me") do |user|
        if user.name
          yield
        else
          command_reply :notice, "AUTH", "could not connect to campfire: invalid API key"
          shutdown
        end
      end
    rescue Firering::Connection::HTTPError => e
      command_reply :notice, "AUTH", "could not connect to campfire: #{e.message}"
      shutdown
    end

    # Check to see that the nick as provided during the registration
    # process matches the authenticated campfire user. If the nicks don't
    # match, send a nick change to the connected client.
    def check_nick_matches_authenticated_user
      campfire.user("me") do |user|
        name = irc_name user.name
        if name != nick
          user_reply :nick, name
          @nick = name
        end
      end
    end

    def send_welcome
      hostname = Socket.gethostname
      numeric_reply :rpl_welcome, "Welcome to CamperVan, #{nick}!#{user}@#{host}"
      numeric_reply :rpl_yourhost, "Your host is #{hostname}, " +
        "running CamperVan version #{CamperVan::VERSION}"
      # using Time.now instead of a global start time since, well, this
      # particular instance really did just start right now. Give or
      # take a few seconds.
      numeric_reply :rpl_created, "This server was created #{Time.now}"
      numeric_reply :rpl_myinfo, hostname, CamperVan::VERSION,
        # channel modes: invite-only, secret
        "is",
        # user modes: away
        "a"
    end

    def send_luser_info
      numeric_reply :rpl_luserclient, "There is 1 user on 1 channel"
      numeric_reply :rpl_luserop, 0, "IRC Operators online"
      numeric_reply :rpl_luserchannels, 0, "channels formed"
      numeric_reply :rpl_myinfo, "I have 1 client and 0 servers"
    end

    def send_motd
      numeric_reply :rpl_motdstart, ":- MOTD for camper_van -"
      MOTD.split("\n").each do |line|
        numeric_reply :rpl_motd, ":- #{line.strip}"
      end
      numeric_reply :rpl_endofmotd, "END of MOTD"
    end

    def join_channel(name)
      campfire.rooms do |rooms|
        if room = rooms.detect { |r| "#" + irc_name(r.name) == name }
          channel = channels[name] || Channel.new(name, self, room)
          if channel.join
            channels[name] = channel
          end
        else
          numeric_reply :err_nosuchchannel, name, "No such campfire room!"
        end
      end
    end

  end
end

