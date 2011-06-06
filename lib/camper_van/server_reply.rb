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

      # room listing
      :rpl_list => "322",
      :rpl_listend => "323",

      # channel joins
      :rpl_notopic => "331",
      :rpl_topic => "332",
      :rpl_namereply => "353",
      :rpl_endofnames => "366",

      # errors
      :err_nonicknamegiven => "413",
      :err_needmoreparams => "461",
      :err_passwdmismatch => "464",
      # couldn't join the channel, it's locked
      :err_channelisfull => "471",
      :err_inviteonlychan => "473",
      :err_unavailresource => "437"
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

    # TODO spec, refactor
    def user_reply(command, *args)
      reply = ":#{nick}!#{user}@#{host} #{command.to_s.upcase}"
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
