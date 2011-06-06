require "camper_van/version"

require "eventmachine"

module CamperVan
  require "camper_van/irc_proxy" # debug proxy
  require "camper_van/server"    # minimal ircd
  require "camper_van/server_reply"       # server responses and helpers
end
