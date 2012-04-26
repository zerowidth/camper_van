require "spec_helper"

describe CamperVan::User do
  context "when initialized from a firering user" do

    # User = Struct.new(:connection, :id, :name, :email_address, :admin,
    # :created_at, :type, :api_auth_token, :avatar_url)
    let(:firering_user) {
      Firering::User.new(
        nil, 12345, "Joe Q. Bob", "joe_bob@example.com", true, Time.now, "asdf", ""
      )
    }
    let(:user) { CamperVan::User.new(firering_user) }

    it "has a nick" do
      user.nick.must_equal "joe_q_bob"
    end

    it "has a name" do
      user.name.must_equal "Joe Q. Bob"
    end

    it "has an account" do
      user.account.must_equal "joe_bob"
    end

    it "has a server" do
      user.server.must_equal "example.com"
    end

    it "has an id" do
      user.id.must_equal 12345
    end

    it "can be an admin" do
      user.admin?.must_equal true
    end

    context "without an email address" do
      let(:firering_user) {
        Firering::User.new(
          nil, 12345, "Joe Q. Bob", nil, true, Time.now, "asdf", ""
        )
      }

      it "has an unknown account" do
        user.account.must_equal "unknown"
      end

      it "has an unknown server" do
        user.server.must_equal "unknown"
      end
    end

  end
end
