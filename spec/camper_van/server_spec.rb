require "spec_helper"

describe CamperVan::Server do
  it "has a run module method" do
    CamperVan::Server.must_respond_to :run
  end

  class TestServer
    include CamperVan::Server

    attr_reader :sent
    attr_reader :tls_started
    def initialize(*)
      super

      @sent = []
      @tls_started = false
    end

    def start_tls(*)
      @tls_started = true
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

  describe "#post_init" do
    it "starts TLS if the ssl option is true" do
      @server = TestServer.new(:ssl => true)

      @server.post_init
      @server.tls_started.must_equal true
    end

    it "does not start TLS if the ssl option is not true" do
      @server = TestServer.new

      @server.post_init
      @server.tls_started.must_equal false
    end
  end

  describe "#receive_line" do
    it "allows for a failed attempt at registration" do
      @server = TestServer.new
      @server.post_init

      @server.receive_line "PASS invalid"
      @server.receive_line "NICK nathan" # ignored
      @server.receive_line "USER nathan 0 0 :Nathan" # ignored

      @server.sent.first.must_match /must specify/
    end
  end

end
