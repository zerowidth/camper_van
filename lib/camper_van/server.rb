module CamperVan

  # The core EventMachine server instance that listens for IRC
  # connections and maps them to IRCD instances.
  module Server
    # Public: start the server
    #
    # bind_address - what address to bind to
    # port         - what port to listen on
    # options      - an optional hash of additional configuration
    #                :log_level - defaults to 'info'
    #                :log_to - log to filename (string), IO. defaults to STDOUT
    #                :ssl - use ssl for client connections, defaults to false
    #                :ssl_private_key - if using ssl, private key file to use, defaults to self-signed
    #                :ssl_cert - if using ssl, cert file to use, defaults to self-signed
    #                :ssl_verify_peer - if using ssl, verify client certificates, defaults to false
    def self.run(bind_address="localhost", port=6667, options={})

      initialize_logging options

      EM.run do
        logger = Logging.logger[self.name]
        logger.info "starting server on #{bind_address}:#{port}"
        EM.start_server bind_address, port, self, options
        trap("INT") do
          logger.info "SIGINT, shutting down"
          EM.stop
        end
      end
    end

    # Initialize the logging system
    #
    # opts - Hash of logging options
    #        - :log_level (default :info)
    #        - :log_to - where to log to (default STDOUT), can be IO or
    #                    String for log filename
    def self.initialize_logging(opts={})
      Logging.consolidate("CamperVan")

      Logging.logger.root.level = opts[:log_level] || :info

      appender = case opts[:log_to]
      when String
        Logging.appenders.file(opts[:log_to])
      when IO
        Logging.appenders.io(opts[:log_to])
      when nil
        Logging.appenders.stdout
      end

      # YYYY-MM-DDTHH:MM:SS 12345 LEVEL LoggerName : The Log message
      appender.layout = Logging::Layouts::Pattern.new(:pattern => "%d %5p %5l %c : %m\n")

      Logging.logger.root.add_appenders appender
    end

    # Using a line-based protocol
    include EM::Protocols::LineText2

    include Logger

    # Public: returns the instance of the ircd for this connection
    attr_reader :ircd

    # Public: returns connection options
    attr_reader :options

    def initialize(options={})
      @options = options
    end

    # Public callback once a server connection is established.
    #
    # Initializes an IRCD instance for this connection.
    def post_init(*args)
      logger.info "got connection from #{remote_ip}"

      # initialize the line-based protocol: IRC is \r\n
      @lt2_delimiter = "\r\n" if @options[:crlf]

      # start up the IRCD for this connection
      @ircd = IRCD.new(self)

      if options[:ssl]
        logger.info "starting TLS for #{remote_ip}"
        start_tls(:cert_chain_file => options[:ssl_cert], :private_key_file => options[:ssl_private_key], :verify_peer => options[:ssl_verify_peer])
      end
    end

    # Public: callback for when a line of the protocol has been
    # received. Delegates the received line to the ircd instance.
    #
    # line - the line received
    def receive_line(line)
      logger.debug "irc -> #{line.strip}"
      ircd.receive_line(line)
    end

    # Public: send a line to the connected client.
    #
    # line - the line to send, sans \r\n delimiter.
    def send_line(line)
      logger.debug "irc <- #{line}"
      send_data line + "\r\n"
    end

    # Public: callback when a client disconnects
    def unbind
      logger.info "closed connection from #{remote_ip}"
    end

    # Public: return the remote ip address of the connected client
    #
    # Returns an IP address string
    def remote_ip
      @remote_ip ||= get_peername[4,4].unpack("C4").map { |q| q.to_s }.join(".")
    end

  end

end
