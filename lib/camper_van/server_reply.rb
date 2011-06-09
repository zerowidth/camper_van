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

      # MODE
      :rpl_channelmodeis      => "324",

      # room listing
      :rpl_list => "322",
      :rpl_listend => "323",
      :rpl_whoreply => "352",
      :rpl_endofwho => "315",

      # channel joins
      :rpl_notopic => "331",
      :rpl_topic => "332",
      :rpl_namereply => "353",
      :rpl_endofnames => "366",

      # errors
      :err_nosuchnick => "401", # no privmsgs to nicks allowed
      :err_nosuchchannel => "403", # no such channel yo

      :err_nonicknamegiven => "413",
      :err_needmoreparams => "461",
      :err_passwdmismatch => "464",

      :err_channelisfull => "471", # room is full
      :err_inviteonlychan => "473", # couldn't join the room, it's locked
      :err_unavailresource => "437" # no such room!
    }

    def numeric_reply(code, *args)
      number = NUMERIC_REPLIES[code]
      raise ArgumentError, "unknown code #{code}" unless number
      send_line ":camper_van #{number} #{nick}" << reply_args(args)
    end

    def command_reply(command, *args)
      send_line ":camper_van #{command.to_s.upcase}" << reply_args(args)
    end

    def user_reply(command, *args)
      send_line ":#{nick}!#{user}@#{host} #{command.to_s.upcase}" << reply_args(args)
    end

    def campfire_reply(command, username, *args)
      send_line ":#{username}!#{username}@campfire #{command.to_s.upcase}" << reply_args(args)
    end

    private

    def reply_args(args)
      reply = ""
      if args.size > 0
        if args.last =~ /\s/ && !args.last.start_with?(':')
          args[-1] = ':' + args.last
        end
        reply << " " << args.join(" ")
      end
      reply
    end

  end
end
