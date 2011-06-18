module CamperVan
  module Server
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

    include EM::Protocols::LineText2

    attr_reader :ircd

    def post_init(*args)
      @lt2_delimiter = "\r\n"
      @ircd = IRCD.new(self)
    end

    def receive_line(line)
      puts "> #{line.strip}"
      ircd.receive_line(line)
    end

    def send_line(line)
      puts "< #{line}"
      send_data line + "\r\n"
    end

  end

end
