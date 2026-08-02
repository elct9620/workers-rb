# frozen_string_literal: true

require "bundler/setup"
require "open-uri"
require "rake/testtask"
require "tmpdir"
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

# The suite drives a real database server rather than a stand-in, so what the
# DB Binding is tested against is what the cluster runs. Like the guest binary
# it ships as a release asset and is pinned here, so the version the suite
# proves the Host against is one the operator can point at.
SQLD_VERSION = "0.24.32"
SQLD_TARGET = [
  RbConfig::CONFIG["host_cpu"] == "x86_64" ? "x86_64" : "aarch64",
  RbConfig::CONFIG["host_os"].include?("darwin") ? "apple-darwin" : "unknown-linux-gnu"
].join("-")
SQLD_BINARY = "vendor/sqld-#{SQLD_VERSION}"
SQLD_RELEASE = "https://github.com/tursodatabase/libsql/releases/download/libsql-server-v#{SQLD_VERSION}"

file SQLD_BINARY do |task|
  mkdir_p File.dirname(task.name)
  # The suite finds the server by looking rather than by version, so one left
  # behind by an upgrade would be a second answer to which one it drives.
  rm_f FileList["vendor/sqld-*"].exclude(task.name)
  Dir.mktmpdir do |staging|
    archive = File.join(staging, "sqld.tar.xz")
    URI.parse("#{SQLD_RELEASE}/libsql-server-#{SQLD_TARGET}.tar.xz")
       .open { |remote| IO.copy_stream(remote, archive) }
    # The release carries a licence and a readme beside the server; only the
    # server is what the suite needs.
    sh "tar", "-xJf", archive, "-C", staging, "libsql-server-#{SQLD_TARGET}/sqld"
    mv File.join(staging, "libsql-server-#{SQLD_TARGET}", "sqld"), task.name
  end
  chmod 0o755, task.name
end

namespace :sqld do
  desc "Download the database server the suite drives"
  task fetch: SQLD_BINARY
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

CHART = "charts/workers"
CHART_SHARED = "sharedDirectory.existingClaim=tenants"

# Every shape an operator can ask this chart for. Nothing here reaches a
# cluster: what is checked is that the chart has an answer for each, because
# a template that only ever rendered one of them would say so in a cluster
# and nowhere earlier.
CHART_RENDERS = {
  "the install the README gives" => CHART_SHARED,
  "a volume the cluster provisions rather than one it already has" => "sharedDirectory.storageClass=fast",
  "one Host, which is what makes `Env.node` say the same thing every time" => "#{CHART_SHARED},nodes=1",
  "a database server this chart did not install" =>
    "#{CHART_SHARED},databases.deploy=false,databases.url=http://sqld:8080,databases.adminUrl=http://sqld:8081"
}.freeze

# What the chart has to turn away. Each of these leaves a cluster that fails
# silently or disagrees with itself, so it is refused while `helm install`
# runs rather than by a Pod that will not start.
CHART_REFUSALS = {
  "a shared directory named by nothing" => "nodes=1",
  "a database server named by nothing" => "#{CHART_SHARED},databases.deploy=false",
  "a server no Host could create a declared database on" =>
    "#{CHART_SHARED},databases.deploy=false,databases.url=http://sqld:8080"
}.freeze

# Out of the default task for the same reason `e2e` is: `rake` needs Ruby and
# the guest binary, this needs Helm.
namespace :chart do
  desc "Render every shape an operator can ask the chart for, and every one it must refuse"
  task :check do
    sh "helm", "lint", CHART, "--strict", "--set", CHART_SHARED

    CHART_RENDERS.each do |shape, values|
      next if system("helm", "template", "workers", CHART, "--set", values, out: File::NULL)

      raise "#{CHART} could not render #{shape}"
    end

    CHART_REFUSALS.each do |shape, values|
      next unless system("helm", "template", "workers", CHART, "--set", values,
                         out: File::NULL, err: File::NULL)

      raise "#{CHART} rendered #{shape} instead of refusing it"
    end
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

task test: [ "wasm:fetch", "sqld:fetch" ]
task default: :test
