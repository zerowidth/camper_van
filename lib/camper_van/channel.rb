module CamperVan
  class Channel
    attr_reader :channel, :client, :room, :stream

    include Utils

    def initialize(channel, client, room)
      @channel, @client, @room = channel, client, room
    end

    def join
      if room.locked?
        numeric_reply :err_inviteonlychan, "Cannot join #{channel} (locked)"
        return false
      elsif room.full?
        numeric_reply :err_channelisfull, "Cannot join #{channel} (full)"
        return false
      else

        # good to go!
        room.join do
          room.users do |users|
            client.user_reply :join, ":#{channel}"
            client.numeric_reply :rpl_topic, channel, ':' + room.topic
            # will include myself, now that i've joined explicitly
            # TODO force nick change to match campfire nick based on
            # auth key / "me" value -- do this at registration time
            users.each_slice(10) do |list|
              names = list.map { |u| irc_name(u.name) }.join(" ")
              client.numeric_reply :rpl_namereply, "=", channel, ":#{names}"
            end
            client.numeric_reply :rpl_endofnames, channel, "End of /NAMES list."
            start_streaming
          end
        end

      end

      true
    end

    def part
      client.user_reply :part, channel
      stream.close_connection if stream
      # room.leave # ehhhh let the timeout do it
    end

    # Replies to a WHO command with a list of users,
    # including their nicks, names, and status.
    #
    # For WHO response http://www.mircscripts.org/forums.php?cid=3&id=159227
    # In short, H = here, G = away
    def list_users
      room.users do |users|
        users.each do |user|
          account, server = user.email_address.split("@")
          nick = irc_name(user.name)
          client.numeric_reply :rpl_whoreply, channel, account, server,
            "camper_van", nick, "H", ":0 #{user.name}"
        end
        client.numeric_reply :rpl_endofwho, channel, "End of WHO list"
      end
    end

    # TODO away message?

    # TODO handle multiple rapid messages for auto-pasting, or
    # P or PASTE command, followed by privmsgs, followed by P or PASTE again?
    def privmsg(msg)
      room.text(msg) { |msg| }
    end

    def start_streaming
    # Public: sends the current channel mode to the client
    def current_mode
      n = room.membership_limit
      s = room.open_to_guests? ? "" : "s"
      i = room.locked? ? "i" : ""
      client.numeric_reply :rpl_channelmodeis, channel, "+#{i}l#{s}", n
    end

      @stream = room.stream do |message|
        case
        when message.advertisement?
          # skip
        when message.allow_guests?
          # secret channel (+i)
        when message.disallow_guests?
          # unsecret channel (-s)
        when message.idle?
          # devoice user
        when message.unidle?
          # voice user
        when message.kick?
          # PART user
        when message.leave?
          # PART user
        when message.paste?
          # send first three lines, plus url for the remainder
        when message.sound?
          # skip, or /ACTION *sound*
        when message.system?
          # NOTICE from :camper_van to channel?
        when message.text?
          # TODO keep registry of user_id / user lookups
          message.user do |user|
            name = irc_name(user.name)
            # TODO again, need to set own nick to campfire nick so
            # this matching will work correctly
            if name == client.nick
              puts "* skipping message from myself"
            else
              client.campfire_reply :privmsg, name, channel, message.body
            end
          end
        when message.timestamp?
          # ?
        when message.topic_change?
          # change channel topic
        when message.type == "LockMessage" # not in the firering API
          # set mode +i and send notice
        when message.unlock?
          # set mode -i and send notice
        when message.upload?
          # ACTION "uploaded #{filename}: #{url}
        else
          puts "* skipping message #{message.type}: #{message.inspect}"
        end
      end
    end

  end
end

