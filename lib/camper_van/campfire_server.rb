require "socket"

module CamperVan
  class CampfireServer
    attr_reader :client
    attr_reader :subdomain, :api_key, :nick, :user, :host

    MOTD = <<-motd
      Welcome to CamperVan.
      To see what campfire rooms are available to the
      configured subdomain and api key, use the LIST command.
    motd

    include CommandDefinition
    include CommandParser
    include ServerReply
    include Utils

    def initialize(client)
      @client = client
      @active = true
    end

    def campfire
      @campfire ||= Firering::Connection.new("http://#{subdomain}.campfirenow.com") do |c|
        c.token = api_key
      end
    end

    def receive_line(line)
      cmd = parse(line)
      handle cmd
    rescue HandlerMissing
      puts "* skipping #{cmd.inspect}: no handler"
    end

    def send_line(line)
      client.send_line line if @active
    end

    def shutdown
      @active = false
      client.close_connection
    end

    handle :pass do |args|
      if args.empty?
        numeric_reply :err_needmoreparams, ":must specify a password: subdomain:api_key"
        shutdown
      else
        @subdomain, @api_key = *args.first.split(":")
      end
    end

    handle :nick do |args|
      if args.empty?
        numeric_reply :err_nonicknamegiven, ":no nickname given"
      else
        @nick = args.first
      end
    end

    handle :user do |args|
      if args.size < 4
        numeric_reply :err_needmoreparams, "Need more params"
      else
        @user = args.first
        @host = client.get_peername[4,4].unpack("C4").map { |q| q.to_s }.join(".")

        unless @api_key
          command_reply :notice, "AUTH", "*** must specify campfire API key as password ***"
          shutdown
        end

        send_welcome
        send_luser_info
        send_motd
      end
    end

    handle :ping do |args|
      command_reply :pong, *args
    end

    handle :list do |args|
      begin
        # hooray async code: have to do gymnastics to make this appear
        # sequential.
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
      rescue Firering::Connection::HTTPError => e
        shutdown
      end
    end

    handle :join do |args|
      args.each do |channel|
        join_channel channel
      end
    end

    def send_welcome
      hostname = Socket.gethostname
      numeric_reply :rpl_welcome, "Welcome to CamperVan, #{nick}!#{user}@#{host}"
      numeric_reply :rpl_yourhost, "Your host is #{hostname}, " +
        "running CamperVan version #{CamperVan::VERSION}"
      # using now instead of a global start time since, well, this
      # particular instance really did just start right now. Give or
      # take a few seconds.
      numeric_reply :rpl_created, "This server was created #{Time.now}"
      numeric_reply :rpl_myinfo, hostname, CamperVan::VERSION,
        # channel modes: invite-only
        "i",
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

    # TODO make irc-safe substitutions, etc.
    def irc_name(name)
      name.gsub('/', '-').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        gsub(/\s+/, "_").
        tr("-", "_").
        downcase
    end

    def join_channel(channel)
      campfire.rooms do |rooms|
        if room = rooms.detect { |r| "#" + irc_name(r.name) == channel }
          if room.locked?
            numeric_reply :err_inviteonlychan, "Cannot join #{channel} (locked)"
          elsif room.full?
            numeric_reply :err_channelisfull, "Cannot join #{channel} (full)"
          else
            # good to go!
            room.join do
              room.users do |users|
                user_reply :join, ":#{channel}"
                numeric_reply :rpl_topic, channel, ':' + room.topic
                # will include myself, now that i've joined explicitly
                # TODO force nick change to match campfire nick based on
                # auth key / "me" value -- do this at registration time
                users.each_slice(10) do |list|
                  names = list.map { |u| irc_name(u.name) }.join(" ")
                  numeric_reply :rpl_namereply, "=", channel, ":#{names}"
                end
                numeric_reply :rpl_endofnames, channel, "End of /NAMES list."
              end
            end
          end
        else
          numeric_reply :err_unavailresource, "That's not a campfire room!"
        end
      end
    end

  end
end
