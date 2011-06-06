module CamperVan
  module Server
    def self.run(bind_address="localhost", port=6667)
      EM.run do
        puts "* starting..."
        EM.start_server bind_address, port, self
      end
    end

    include EM::Protocols::LineText2

    attr_reader :campfire_server

    def post_init(*args)
      @lt2_delimiter = "\r\n"
      @campfire_server = CampfireServer.new(self)
    end

    def receive_line(line)
      puts "> #{line.strip}"
      campfire_server.receive_line(line)
    end

    def send_line(line)
      puts "< #{line}"
      send_data line + "\r\n"
    end

  end

end
