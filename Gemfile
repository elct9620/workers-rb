# frozen_string_literal: true

source "https://rubygems.org"

# The WASM/mruby sandbox tenant code runs inside. The gem bundles only the
# pure guest binary; the variant workers-rb needs is fetched separately and
# pinned to whatever version resolves here — see `rake wasm:fetch`.
gem "kobako", "~> 0.21.1"

gem "puma", "~> 8.0"
gem "sinatra", "~> 4.2"

group :development do
  gem "minitest", "~> 6.0"
  gem "rack-test", "~> 2.2"
  gem "rake", "~> 13.0"
  gem "rubocop-rails-omakase", require: false
end
