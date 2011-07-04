require "camper_van/version"

require "eventmachine"
require "firering"
require "logging"

module CamperVan
  require "camper_van/debug_proxy"        # debug proxy

  require "camper_van/utils"              # utility methods
  require "camper_van/logger"             # logging helper
  require "camper_van/command_parser"     # irc command parser
  require "camper_van/command_definition" # command definition and processing
  require "camper_van/server_reply"       # ircd responses and helpers
  require "camper_van/user"               # channel/campfire user

  require "camper_van/ircd"               # ircd server
  require "camper_van/channel"            # campfire room <-> channel bridge

  require "camper_van/server"             # the core campfire EM server

  # Public: return the logger for the module
  #
  # Returns a Logging::Logger instance.
  def self.logger
    @logger = Logging::Logger[self.name]
  end
end
