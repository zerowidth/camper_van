module CamperVan
  class Channel
    attr_reader :channel, :client, :room, :stream

    include Utils

    # Public: create a new campfire channel
    #
    # channel - name of the channel we're joining
    # client  - the EM::Connection representing the irc client
    # room    - the campfire room we're joining
    def initialize(channel, client, room)
      @channel, @client, @room = channel, client, room
    end

    # Public: Joins a campfire room and sends the necessary topic
    # and name list messages back to the IRC client.
    #
    # Returns true if the join was successful,
    #   false if the room was full or locked.
    def join
      if room.locked?
        numeric_reply :err_inviteonlychan, "Cannot join #{channel} (locked)"
        return false
      elsif room.full?
        numeric_reply :err_channelisfull, "Cannot join #{channel} (full)"
        return false
      else

        # good to go, join the room and get the list of users
        room.join do
          room.users do |users|
            # update_user_list users
            # join channel
            client.user_reply :join, ":#{channel}"
            client.numeric_reply :rpl_topic, channel, ':' + room.topic
            # will include myself, now that i've joined explicitly
            users.each_slice(10) do |list|
              names = list.map { |u| irc_name(u.name) }.join(" ")
              client.numeric_reply :rpl_namereply, "=", channel, ":#{names}"
            end
            client.numeric_reply :rpl_endofnames, channel, "End of /NAMES list."

            # begin streaming the channel
            stream_campfire_to_channel
          end
        end

      end

      true
    end

    # Public: "leaves" a campfire room, per the PART irc command.
    # Confirms with the connected client to PART the channel.
    # Does not actually leave the room, just closes out the campfire
    # connections, so the server can idle the connection out. This behavior
    # was chosen so periodic joins/parts wouldn't spam the campfire rooms
    # unnecessarily, and also to reflect how Propane et. al. treat open
    # connections: allowing them to time out rather than leaving explicitly.
    def part
      client.user_reply :part, channel
      stream.close_connection if stream
      # room.leave # let the timeout do it
    end

    # Public: replies to a WHO command with a list of users for a campfire room,
    # including their nicks, names, and status.
    #
    # For WHO response: http://www.mircscripts.org/forums.php?cid=3&id=159227
    # In short, H = here, G = away
    #
    # TODO: handle away / maintain list state / etc.
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

    # Public: accepts an IRC PRIVMSG and converts it to an appropriate
    # campfire text message for the room.
    #
    # msg - the IRC PRIVMSG message contents
    #
    # TODO: substitute "nick: " with the nick's campfire name
    def privmsg(msg)

      # convert ACTIONs
      msg.sub! /^\01ACTION (.*)\01$/, '*\1*'

      room.text(msg) { } # async, no-op callback
    end

    # Public: sends the current channel mode to the client
    def current_mode
      n = room.membership_limit
      s = room.open_to_guests? ? "" : "s"
      i = room.locked? ? "i" : ""
      client.numeric_reply :rpl_channelmodeis, channel, "+#{i}l#{s}", n
    end

    # Public: set the mode on the campfire channel, mapping from the provided
    # IRC chanmode to the campfire setting.
    #
    # mode - the IRC mode flag change. Must be one of:
    #        "+s" - disable guest access
    #        "-s" - enable guest access
    #        "+i" - lock room
    #        "-i" - unlock room
    #
    # Returns nothing, but lets the client know the results of the call. Sends
    #   an error to the client for an invalid mode string.
    def set_mode(mode)
      case mode
      when "+s"
      when "-s"
      when "+i"
      when "-i"
      else
        client.numeric_reply
      end
    end

    # Public: returns the current topic of the campfire room
    def current_topic
      client.numeric_reply :rpl_topic, channel, ':' + room.topic
    end

    # Public: set the topic of the campfire room to the given string
    # and lets the irc client know about the change
    #
    # topic - the new topic
    def set_topic(topic)
      room.update("topic" => topic) do
        room.topic = topic
        client.numeric_reply :rpl_topic, channel, ':' + room.topic
      end
    end

    # Stream messages from campfire and map them to IRC commands for the
    # connected client.
    def stream_campfire_to_channel
      @stream = room.stream do |message|
        map_message_to_irc message
      end
    end

    # Map a campfire message to one or more IRC commands for the client
    #
    # message - the campfire message to map to IRC
    def map_message_to_irc(message)
      # strip Message off the type to simplify readability
      case message.type.sub(/Message$/,'')

      when "Timestamp", "Advertisement"
        # ignore these

      when "Lock"
        message.user do |user|
          name = irc_name(user.name)
          client.campfire_reply :mode, name, channel, "+i"
        end

      when "Unlock"
        message.user do |user|
          name = irc_name(user.name)
          client.campfire_reply :mode, name, channel, "-i"
        end

      when "DisallowGuests"
        message.user do |user|
          name = irc_name(user.name)
          client.campfire_reply :mode, name, channel, "+s"
        end

      when "AllowGuests"
        message.user do |user|
          name = irc_name(user.name)
          client.campfire_reply :mode, name, channel, "-s"
        end

      # when "Idle"
        # message.user do |user|
        #   name = irc_name(user.name)
        #   # set status of user in list to "idle"
        # end

      # when "Unidle"
        # message.user do |user|
        #   name = irc_name(user.name)
        #   # set status of user in list to "idle"
        # end

      when "Enter"
        message.user do |user|
          name = irc_name(user.name)
          client.campfire_reply :join, name, channel
        end
        # TODO add to tracking list

      when "Leave", "Kick" # kick is used for idle timeouts
        message.user do |user|
          name = irc_name(user.name)
          client.campfire_reply :part, name, channel, "Leaving..."
          # TODO remove from active user list
        end

      when "Paste"
        message.user do |user|
          name = irc_name(user.name)
          lines = message.body.split("\n")

          lines[0..2].each do |line|
            client.campfire_reply :privmsg, name, channel, "> " + line
          end

          if lines.size > 3
            client.campfire_reply :privmsg, name, channel, "> more: " +
              "https://#{client.subdomain}.campfirenow.com/room/#{room.id}/paste/#{message.id}"
          end
        end

      # when "Sound"
      #   # skip, or /ACTION *sound*

      # when "System"
      #   # NOTICE from :camper_van to channel?

      when "Text"
        message.user do |user|
          # TODO keep registry of user_id / user lookups
          name = irc_name(user.name)
          if name == client.nick
            puts "* skipping message from myself: #{message.type} #{message.inspect}"
          else
            if message.body =~ /^\*.*\*$/
              client.campfire_reply :privmsg, name, channel, ":\01ACTION " + message.body[1..-2] + "\01"
            else
              client.campfire_reply :privmsg, name, channel, message.body
            end
          end
        end

      when "Topic"
        client.numeric_reply :rpl_topic, channel, ':' + message.body
        room.topic = message.body

      when "Upload"
        message.user do |user|
          name = irc_name(user.name)
          client.campfire_reply :privmsg, name, channel, ":\01ACTION uploaded " +
            "https://#{client.subdomain}.campfirenow.com/room/#{room.id}/uploads/#{message.id}/#{message.body}"
        end

      else
        puts "* unknown message #{message.type}: #{message.inspect}"
      end
    end

  end
end

