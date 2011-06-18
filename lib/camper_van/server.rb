module CamperVan

  # The core EventMachine server instance that listens for IRC
  # connections and maps them to IRCD instances.
  module Server

    # Public: start the server
    #
    # bind_address - what address to bind to
    # port         - what port to listen on
    def self.run(bind_address="localhost", port=6667)
      EM.run do
        puts "* starting..."
        EM.start_server bind_address, port, self
        trap("INT") do
          puts"* shutting down..."
          EM.stop
        end
      end
    end

    # Using a line-based protocol
    include EM::Protocols::LineText2

    attr_reader :ircd

    # Public callback once a server connection is established.
    #
    # Initializes an IRCD instance for this connection.
    def post_init(*args)
      # initialize the line-based protocol: IRC is \r\n
      @lt2_delimiter = "\r\n"

      # start up the IRCD for this connection
      @ircd = IRCD.new(self)
    end

    # Public: callback for when a line of the protocol has been
    # received. Delegates the received line to the ircd instance.
    #
    # line - the line received
    def receive_line(line)
      puts "> #{line.strip}"
      ircd.receive_line(line)
    end

    # Public: send a line to the connected client.
    #
    # line - the line to send, sans \r\n delimiter.
    def send_line(line)
      puts "< #{line}"
      send_data line + "\r\n"
    end

  end

end
