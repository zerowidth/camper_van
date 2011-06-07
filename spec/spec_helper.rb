require "bundler"

Bundler.setup :default, :development

require "minitest/spec"
require "minitest/autorun"
require "minitest-rg"

require "camper_van"

alias :context :describe
