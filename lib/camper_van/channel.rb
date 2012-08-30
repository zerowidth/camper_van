# encoding: utf-8

require "yaml"

module CamperVan
  class Channel

    # The irc channel name this channel instance is for
    attr_reader :channel

    # The connected irc client connection
    attr_reader :client

    # The campfire room to which this channel is connected
    attr_reader :room

    # Accessor for the EM http request representing the live stream from
    # the campfire api
    attr_reader :stream

    # Accessor for hash of known users in the room/channel
    # Kept up to date by update_users command, as well as Join/Leave
    # campfire events.
    attr_reader :users

    include Utils
    include Logger

    # Public: create a new campfire channel
    #
    # channel - name of the channel we're joining
    # client  - the EM::Connection representing the irc client
    # room    - the campfire room we're joining
    def initialize(channel, client, room)
      @channel, @client, @room = channel, client, room
      @users = {}
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
        update_users do
          # join channel
          client.user_reply :join, ":#{channel}"

          # current topic
          client.numeric_reply :rpl_topic, channel, ':' + room.topic

          # List the current users, which must always include myself
          # (race condition, server may not realize the user has joined yet)
          nicks = users.values.map { |u| u.nick }
          nicks.unshift client.nick unless nicks.include? client.nick

          nicks.each_slice(10) do |list|
            client.numeric_reply :rpl_namereply, "=", channel, ":#{list.join ' '}"
          end
          client.numeric_reply :rpl_endofnames, channel, "End of /NAMES list."

          # begin streaming the channel events (joins room implicitly)
          stream_campfire_to_channel
        end
      end

      true
    end

    # Public: "leaves" a campfire room, per the PART irc command.
    # Confirms with the connected client to PART the channel.
    #
    # Does not actually leave the campfire room, just closes out the campfire
    # connections, so the server can idle the connection out. This behavior
    # was chosen so periodic joins/parts wouldn't spam the campfire rooms
    # unnecessarily, and also to reflect how Propane et. al. treat open
    # connections: allowing them to time out rather than leaving explicitly.
    def part
      client.user_reply :part, channel
      # FIXME this doesn't work. Not even on next_tick. EM/em-http-request bug?
      stream.close_connection if stream
      # room.leave # let the timeout do it rather than being explicit!
    end

    # Public: replies to a WHO command with a list of users for a campfire room,
    # including their nicks, names, and status.
    #
    # For WHO response: http://www.mircscripts.org/forums.php?cid=3&id=159227
    # In short, H = here, G = away, append @ for chanops (admins)
    def list_users
      update_users(:include_joins_and_parts) do
        users.values.each do |user|
          status = (user.idle? ? "G" : "H") + (user.admin? ? "@" : "")
          client.numeric_reply :rpl_whoreply, channel, user.account, user.server,
            "camper_van", user.nick, status, ":0 #{user.name}"
        end
        client.numeric_reply :rpl_endofwho, channel, "End of WHO list"
      end
    end

    # Public: accepts an IRC PRIVMSG and converts it to an appropriate
    # campfire text message for the room.
    #
    # msg - the IRC PRIVMSG message contents
    #
    def privmsg(msg)

      # convert twitter urls to tweets
      if msg =~ %r(^https://twitter.com/(\w+)/status/(\d+)$)
        room.tweet(msg) { } # async, no-op callback
      else
        # convert ACTIONs
        msg.sub! /^\01ACTION (.*)\01$/, '*\1*'

        matched = users.values.detect do |user|
          msg =~ /^#{Regexp.escape(user.nick)}($|\W+(\s|$))/
        end

        msg = msg.sub(/^#{matched.nick}/, matched.name) if matched

        room.text(msg) { } # async, no-op callback
      end

    end

    # Public: sends the current channel mode to the client
    def current_mode
      n = room.membership_limit
      client.numeric_reply :rpl_channelmodeis, channel, current_mode_string, n
    end

    # Public: set the mode on the campfire channel, mapping from the provided
    # IRC chanmode to the campfire setting.
    #
    # mode - the IRC mode flag change. Must be one of:
    #        "+i" - lock room
    #        "-i" - unlock room
    #
    # TODO support these when the firering client does:
    #        "+s" - disable guest access
    #        "-s" - enable guest access
    #
    # Returns nothing, but lets the client know the results of the call. Sends
    #   an error to the client for an invalid mode string.
    def set_mode(mode)
      case mode
      # when "+s"
      # when "-s"
      when "+i"
        room.lock
        room.locked = true
        client.user_reply :mode, channel,
          current_mode_string, room.membership_limit
      when "-i"
        room.unlock
        room.locked = false
        client.user_reply :mode, channel,
          current_mode_string, room.membership_limit
      else
        client.numeric_reply :err_unknownmode,
          "is unknown mode char to me for #{channel}"
      end
    end

    # Returns the current mode string
    def current_mode_string
      n = room.membership_limit
      s = room.open_to_guests? ? "" : "s"
      i = room.locked? ? "i" : ""
      "+#{i}l#{s}"
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

    # Get the list of users from a room, and update the internal
    # tracking state as well as the connected client. If the user list
    # is out of sync, the irc client may receive the associated
    # JOIN/PART commands.
    #
    # include_joins_and_parts - whether or not to include JOIN/PART commands if
    #                           the user list has changed since the last update
    #                           (defaults to false)
    # callback                - optional callback after the users have been
    #                           updated
    #
    # Returns nothing, but keeps the users list updated
    def update_users(include_joins_and_parts=false, &callback)
      room.users do |user_list|
        before = users.dup
        present = {}

        user_list.each do |user|
          if before[user.id]
            present[user.id] = before.delete user.id
            # if present[user.id].nick != nick
            #   # NICK CHANGE
            #   present[user.id].nick = nick
            # end
          else
            new_user = present[user.id] = User.new(user)
            if include_joins_and_parts
              client.campfire_reply :join, new_user.nick, channel
            end
          end
        end

        # Now that the list of users is updated, the remaining users
        # in 'before' have left. Let the irc client know.
        before.each do |id, user|
          if include_joins_and_parts
            client.campfire_reply :part, user.nick, channel
          end
        end

        @users = present

        callback.call if callback
      end
    end

    # Stream messages from campfire and map them to IRC commands for the
    # connected client.
    #
    # Only starts the stream once.
    def stream_campfire_to_channel
      @stream ||= room.stream do |message|
        map_message_to_irc message
      end
    end

    # Map a campfire message to one or more IRC commands for the client
    #
    # message - the campfire message to map to IRC
    #
    # Returns nothing, but responds according to the message
    def map_message_to_irc(message)
      user_for_message(message) do |message, user|

        # needed in most cases
        name = user ? irc_name(user.name) : nil

        # strip Message off the type to simplify readability
        type = message.type.sub(/Message$/, '')

        if %w(Text Tweet Sound Paste Upload).include?(type) && name == client.nick
            logger.debug "skipping message from myself: #{message.type} #{message.body}"
          next
        end

        case type
        when "Timestamp", "Advertisement"
          # ignore these

        when "Lock"
          client.campfire_reply :mode, name, channel, "+i"

        when "Unlock"
          client.campfire_reply :mode, name, channel, "-i"

        when "DisallowGuests"
          name = irc_name(user.name)
          client.campfire_reply :mode, name, channel, "+s"

        when "AllowGuests"
          name = irc_name(user.name)
          client.campfire_reply :mode, name, channel, "-s"

        when "Idle"
          if u = users[user.id]
            u.idle = true
          end

        when "Unidle"
          if u = users[user.id]
            u.idle = false
          end

        when "Enter"
          unless users[user.id]
            client.campfire_reply :join, name, channel
            users[user.id] = User.new(user)
          end

        when "Leave", "Kick" # kick is used for idle timeouts
          client.campfire_reply :part, name, channel, "Leaving..."
          users.delete user.id

        when "Paste"
          lines = message.body.split("\n")

          lines[0..2].each do |line|
            client.campfire_reply :privmsg, name, channel, ":> " + line
          end

          if lines.size > 3
            client.campfire_reply :privmsg, name, channel, ":> more: " +
              "https://#{client.subdomain}.campfirenow.com/room/#{room.id}/paste/#{message.id}"
          end

        when "Sound"
          text = case message.body
          when "crickets"
            "hears crickets chirping"
          when "rimshot"
            "plays a rimshot"
          when "trombone"
            "plays a sad trombone"
          when "vuvuzela"
            "======<() ~ ♪ ~♫"
          else
            "played a #{message.body} sound"
          end

          client.campfire_reply :privmsg, name, channel, "\x01ACTION #{text}\x01"

        # when "System"
        #   # NOTICE from :camper_van to channel?

        when "Text"
          if message.body =~ /^\*.*\*$/
            client.campfire_reply :privmsg, name, channel, ":\01ACTION " + message.body[1..-2] + "\01"
          else
            matched = users.values.detect do |user|
              message.body =~ /^#{Regexp.escape(user.name)}(\W+(\s|$)|$)/
            end

            if matched
              body = message.body.sub(/^#{matched.name}/, matched.nick)
            else
              body = message.body
            end
            client.campfire_reply :privmsg, name, channel, ":" + body
          end

        when "TopicChange"
          client.campfire_reply :topic, name, channel, message.body
          room.topic = message.body
          # client.numeric_reply :rpl_topic, channel, ':' + message.body

        when "Upload"
          client.campfire_reply :privmsg, name, channel, ":\01ACTION uploaded " +
            "https://#{client.subdomain}.campfirenow.com/room/#{room.id}/uploads/#{message.id}/#{message.body}"

        when "Tweet"
          # stringify keys since campfire API is inconsistent about it
          tweet = stringify_keys(YAML.load(message.body))
          client.campfire_reply :privmsg, name, channel,
            "@#{tweet["author_username"]}: #{tweet["message"]}" +
            " (https://twitter.com/#{tweet["author_username"]}" +
            "/status/#{tweet["id"]})"

        else
          logger.warn "unknown message #{message.type}: #{message.body}"
        end
      end
    end

    # Retrieve the user from a message, either by finding it in the current
    # list of known users, or by asking campfire for the user.
    #
    # message - the message for which to look up the user
    #
    # Yields the message and the user associated with the message
    def user_for_message(message)
      if user = users[message.user_id]
        yield message, user
      else
        message.user do |user|
          yield message, user
        end
      end
    end

  end
end

