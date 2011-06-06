require "camper_van/version"

require "eventmachine"

module CamperVan
  require "camper_van/irc_proxy"          # debug proxy
  require "camper_van/command_parser"     # irc command parser
  require "camper_van/command_definition" # command definition and processing
  require "camper_van/server_reply"       # server responses and helpers
  require "camper_van/campfire_server"    # ircd server object for campfire
  require "camper_van/server"             # server container for campfire server instance
end
