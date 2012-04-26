module CamperVan
  class User

    # IRC normalization from names
    include Utils

    # Public: the user's campfire id
    attr_reader :id

    # Public: the user's campfire name
    attr_reader :name

    # Public: the user's irc nick
    attr_reader :nick

    # Public: the user's unix account name for user@host pairs in irc,
    # mapped from the user's email address
    attr_reader :account

    # Public: the user's unix server name for user@host pairs in irc,
    # mapped from the user's email address
    attr_reader :server

    # Public: whether the user is idle or not. Updated by campfire
    # Idle/Unidle messages
    def idle?
      @idle
    end

    # Public: set the user's idle state.
    #
    # is_idle - true/false
    attr_writer :idle

    # Public: whether or not the user is an admin
    def admin?
      @admin
    end

    # Public: set the user's admin state
    #
    # admin - true/false
    attr_writer :admin

    # Public: create a new user from a campfire user definition.
    #
    # Initializes the user's fields based on the campfire user info.
    def initialize(user)
      @id = user.id
      @name = user.name
      if user.email_address
        @account, @server = user.email_address.split("@")
      else
        @account = @server = "unknown"
      end
      @nick = irc_name user.name
      @idle = false
      @admin = user.admin
    end

  end
end

