require "spec_helper"

describe CamperVan::Server do
  it "has a run module method" do
    CamperVan::Server.must_respond_to :run
  end

  class TestServer
    include CamperVan::Server

    attr_reader :sent
    def initialize
      @sent = []
    end

    def close_connection
    end

    def send_data(data)
      @sent << data
    end

    def get_peername
      "xx" + [6667, 127, 0, 0, 1].pack("nC4")
    end
  end

  before :each do
    @server = TestServer.new
    @server.post_init
  end

  describe "#receive_line" do
    it "allows for a failed attempt at registration" do
      @server.receive_line "PASS invalid"
      @server.receive_line "NICK nathan" # ignored
      @server.receive_line "USER nathan 0 0 :Nathan" # ignored

      @server.sent.first.must_match /must specify/
    end
  end

end
