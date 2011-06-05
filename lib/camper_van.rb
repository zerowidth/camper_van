require "camper_van/version"

require "eventmachine"

module CamperVan
  require "camper_van/irc_proxy" # debug proxy
  require "camper_van/server"    # minimal ircd
end
