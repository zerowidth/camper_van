module CamperVan
  module Utils
    # TODO make irc-safe substitutions, etc.
    def irc_name(name)
      name.gsub('/', '-').
        gsub(/\W/, ' ').
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        gsub(/\s+/, "_").
        tr("-", "_").
        downcase
    end

  end
end
