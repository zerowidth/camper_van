require "bundler"

Bundler.setup :default, :development

require "minitest/spec"
require "minitest/autorun"
require "minitest/mock"
require "minitest-rg"

require "ostruct"

require "camper_van"

alias :context :describe
