# debug proxy for dumping all irc traffic between a client and a server
module CamperVan
  class IrcProxy < EM::Connection
    include EM::Protocols::LineText2

    def self.run(server, server_port=6667)
      EM.run do
        EM.start_server "localhost", 6667, IrcProxy, server, server_port
        puts "* waiting for connections..."
      end

      trap("INT") do
        puts "* shutting down"
        EM.stop
      end
    end

    class Server < EM::Connection
      include EM::Protocols::LineText2

      attr_reader :client

      def initialize(client)
        super
        @lt2_delimiter = "\r\n"
        @client = client
      end

      def post_init
        puts "* established connection to server"
      end

      def receive_line(line)
        puts "> #{line}"
        client.send_data line + "\r\n"
      end

      def unbind
        puts "* server closed connection"
      end
    end

    def initialize(server, server_port)
      @server = EM.connect(server, server_port, IrcProxy::Server, self)
      @lt2_delimiter = "\r\n"
    end

    def post_init
      puts "* client connected, establishing connection to server..."
    end

    def receive_line(line)
      puts "< #{line}"
      @server.send_data line + "\r\n"
    end

    def unbind
      puts "* client closed connection"
    end

  end
end
