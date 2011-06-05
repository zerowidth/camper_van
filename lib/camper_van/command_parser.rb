module CamperVan

  # simplistic IRC command parser
  module CommandParser

    # returns hash, e.g.
    #
    #   malformed # => nil
    #   NICK joe # => # { :nick => ["joe"] }
    #   LIST # => # { :list => [] }
    #   PRIVMSG #foo :test # => { :privmsg => ['#foo', 'test'] }
    #
    def parse(line)
      line = line.dup
      match = /^([A-Z]+)(\b|$)/.match(line)
      cmd = match && match[0]

      return nil unless cmd

      # strip off the command and any whitespace
      line.sub! /^#{cmd}\s*/, ""

      args = []
      until line.empty? do
        line =~ /^(\S+)(\s|$)/
        if $1
          if $1.start_with?(":")
            args << line[1..-1]
            break
          else
            args << $1
          end
        else
          break
        end
        line.sub! /^#{$1}\s*/, ""
      end

      return {cmd.downcase.to_sym => args }
    end
  end
end
