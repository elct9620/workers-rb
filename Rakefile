# frozen_string_literal: true

require "bundler/setup"
require "open-uri"
require "rake/testtask"
require "kobako/version"

# Tenant code needs JSON and ASCII Regexp, which the guest binary bundled in
# the gem does not carry. The `+full` variant does, and ships only as a
# release asset. Its version follows the resolved gem so the host side and
# the guest side can never drift apart.
GUEST_BINARY = "vendor/kobako+full-#{Kobako::VERSION}.wasm"
GUEST_RELEASE = "https://github.com/elct9620/kobako/releases/download/v#{Kobako::VERSION}"

file GUEST_BINARY do |task|
  mkdir_p File.dirname(task.name)
  URI.parse("#{GUEST_RELEASE}/#{File.basename(task.name)}")
     .open { |remote| IO.copy_stream(remote, task.name) }
end

namespace :wasm do
  desc "Download the guest binary the Host runs tenant code on"
  task fetch: GUEST_BINARY
end

SAMPLE_TENANT = <<~'RUBY'
  App = ->(env) {
    req = Request.new(env)

    Response.json({
      "tenant" => Env.tenant,
      "node" => Env.node,
      "path" => req.path,
      "time" => Time.now,
      "roll" => Random.rand(6) + 1
    })
  }
RUBY

namespace :dev do
  desc "Write a sample tenant into the directory the Host serves"
  task :tenant do
    dir = File.join(ENV.fetch("WORKERS_APP_DIR", "app"), "hello")
    mkdir_p dir
    File.write(File.join(dir, "app.json"), "{}\n")
    File.write(File.join(dir, "main.rb"), SAMPLE_TENANT)
  end
end

Rake::TestTask.new do |task|
  task.libs << "lib" << "test"
  task.test_files = FileList["test/**/*_test.rb"]
end

task test: "wasm:fetch"
task default: :test
