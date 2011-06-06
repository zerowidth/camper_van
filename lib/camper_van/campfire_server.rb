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

    # TODO support for ISON, used by linkinus
    handle :ison do |args|
      # numeric_reply :rpl_ison, *args
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

  end
end
