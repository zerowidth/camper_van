module CamperVan
  module ServerReply

    # not an exhaustive list, just what i'm using
    NUMERIC_REPLIES = {

      # successful registration / welcome to the network
      :rpl_welcome => "001",
      :rpl_yourhost => "002",
      :rpl_created => "003",
      :rpl_myinfo => "004",

      # more welcome messages
       :rpl_luserclient => "251",
       :rpl_luserop => "252",
       :rpl_luserchannels => "254",
       :rpl_luserme => "255",

       # MOTD
       :rpl_motdstart => "375",
       :rpl_motd => "372",
       :rpl_endofmotd => "376",

      # errors
      :err_nonicknamegiven => "413",
      :err_needmoreparams => "461",
      :err_passwdmismatch => "464"
    }

    def numeric_reply(code, *args)
      number = NUMERIC_REPLIES[code]
      raise ArgumentError, "unknown code #{code}" unless number
      reply = ":camper_van #{number} #{nick}"
      if args.last && args.last =~ /\s/ && !args.last.start_with?(':')
        args[-1] = ':' + args.last
      end
      reply << " #{args.join(" ")}" unless args.empty?
      send_line reply
    end

    def command_reply(command, *args)
      reply = ":camper_van #{command.to_s.upcase}"
      if args.size > 0
        if args.last =~ /\s/ && !args.last.start_with?(':')
          args[-1] = ':' + args.last
        end
        reply << " " << args.join(" ")
      end
      send_line reply
    end

  end
end
