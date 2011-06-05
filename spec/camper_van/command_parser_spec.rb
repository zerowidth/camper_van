require "spec_helper"

describe CamperVan::CommandParser do
  class TestParser
    include CamperVan::CommandParser
  end

  it "defines a parse method on a class that includes it" do
    TestParser.new.must_respond_to :parse
  end

  describe "#parse" do
    before :each do
      @parser = TestParser.new
    end

    it "returns nil for a malformed command" do
      @parser.parse("lolwhat").must_equal nil
    end

    it "parses a LIST command" do
      @parser.parse("LIST").must_equal :list => []
    end

    it "parses a NICK command" do
      @parser.parse("NICK nathan").must_equal :nick => ["nathan"]
    end

    it "parses a PRIVMSG command" do
      @parser.parse("PRIVMSG #chan :hello there").must_equal(
        :privmsg => ["#chan", "hello there"]
      )
    end
  end

end
