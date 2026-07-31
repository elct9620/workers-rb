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

SAMPLE_MANIFEST = <<~'JSON'
  { "bindings": { "db": { "DB::Main": "main" } } }
JSON

SAMPLE_TENANT = <<~'RUBY'
  App = ->(env) {
    req = Request.new(env)

    DB::Main.execute("create table if not exists visits (at real)")
    DB::Main.execute("insert into visits values (?)", Time.now)

    Response.json({
      "tenant" => Env.tenant,
      "node" => Env.node,
      "writer" => Env.writer?,
      "path" => req.path,
      "visits" => DB::Main.query("select count(*) as n from visits")[0]["n"]
    })
  }
RUBY

namespace :dev do
  desc "Write a sample tenant into the directory the Host serves"
  task :tenant do
    dir = File.join(ENV.fetch("WORKERS_APP_DIR", "app"), "hello")
    mkdir_p dir
    File.write(File.join(dir, "app.json"), SAMPLE_MANIFEST)
    File.write(File.join(dir, "main.rb"), SAMPLE_TENANT)

    # The database mount is the operator's to provide; outside a container it
    # is an ordinary directory the Host writes tenant databases into.
    mkdir_p ENV.fetch("WORKERS_DB_DIR", "db")
  end
end

namespace :e2e do
  desc "Publish the tenants the cluster suite drives"
  task :publish do
    dest = ENV.fetch("WORKERS_APP_DIR", "app")
    mkdir_p dest
    cp_r FileList["e2e/app/*"], dest
  end
end

Rake::TestTask.new do |task|
  task.libs << "lib" << "test"
  task.test_files = FileList["test/**/*_test.rb"]
end

# Drives a cluster that is already running, so it stays out of the default
# task: `rake` needs Ruby and the guest binary, this needs Docker.
Rake::TestTask.new(e2e: "e2e:publish") do |task|
  task.description = "Drive the running cluster through its external address"
  task.test_files = FileList["e2e/*_test.rb"]
end

task test: "wasm:fetch"
task default: :test
