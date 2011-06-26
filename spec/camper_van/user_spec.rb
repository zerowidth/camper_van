require "spec_helper"

describe CamperVan::User do
  context "when initialized from a firering user" do
    before :each do
      # User = Struct.new(:connection, :id, :name, :email_address, :admin,
      # :created_at, :type, :api_auth_token, :avatar_url)
      @f_user = Firering::User.new(
        nil, 12345, "Joe Q. Bob", "joe_bob@example.com", true, Time.now, "asdf", ""
      )

      @user = CamperVan::User.new(@f_user)
    end

    it "has a nick" do
      @user.nick.must_equal "joe_q_bob"
    end

    it "has a name" do
      @user.name.must_equal "Joe Q. Bob"
    end

    it "has an account" do
      @user.account.must_equal "joe_bob"
    end

    it "has a server" do
      @user.server.must_equal "example.com"
    end

    it "has an id" do
      @user.id.must_equal 12345
    end

  end
end
