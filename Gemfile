source "http://rubygems.org"

# Specify your gem's dependencies in camper_van.gemspec
gemspec

# specified here rather than in gemspec because they're
# for local mac development only
group :development do
  gem "rb-fsevent", :require => false
  gem "growl", :require => false
  gem "guard"
  # 0.4.0.rc versions are still git-only
  gem "guard-minitest", :git => "https://github.com/guard/guard-minitest.git"
end
