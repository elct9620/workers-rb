# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "rack/test"

require "workers"

module TestHelper
  FIXTURE_APP_DIR = File.expand_path("fixtures/app", __dir__)
end
