# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "camper_van/version"

Gem::Specification.new do |s|
  s.name        = "camper_van"
  s.version     = CamperVan::VERSION
  s.authors     = ["Nathan Witmer"]
  s.email       = ["nwitmer@gmail.com"]
  s.homepage    = "https://github.com/zerowidth/camper_van"
  s.summary     = %q{An IRC to Campfire bridge}
  s.description = %q{An IRC to Campfire bridge for IRC-based access to campfire chatrooms}

  s.rubyforge_project = "camper_van"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.required_ruby_version = "~> 1.9.2"

  s.add_dependency "eventmachine", "~> 0.12.10"
  s.add_dependency "firering", "~> 1.2.0"
  s.add_dependency "logging", "~> 1.5.1"
  s.add_dependency "trollop", "~> 1.16.2"

  s.add_development_dependency "rake"
end
