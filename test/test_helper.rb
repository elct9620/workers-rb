# frozen_string_literal: true

require "bundler/setup"
require "fileutils"
require "minitest/autorun"
require "rack/test"
require "tmpdir"

require "workers"

module TestHelper
  FIXTURE_APP_DIR = File.expand_path("fixtures/app", __dir__)

  # Every test drives the real Host, which keeps its configuration on the
  # class. Starting each test from the same settings is what keeps one test's
  # shared directory or limits out of the next one's.
  class Case < Minitest::Test
    include Rack::Test::Methods

    def setup
      Workers::Host.set :app_dir, FIXTURE_APP_DIR
      Workers::Host.set :node, Workers::Node.current
      Workers::Host.set :databases, Workers::Databases.current
      Workers::Host.set :runtime, Workers::Runtime.default
    end

    def app = Workers::Host

    private

    # A shared directory holding one Tenant, served for the duration of the
    # block. Rack::Test settles its session on a test's first request, so the
    # Host is pointed here directly rather than through `app` — a later
    # request would otherwise still read the directory the first one set.
    def serving(name, manifest: "{}", body: "here", source: worker(body))
      Dir.mktmpdir do |root|
        publish(root, name, manifest: manifest, source: source)
        Workers::Host.set :app_dir, root
        yield root
      ensure
        # A test may leave the directory unreadable; it still has to be
        # removed.
        File.chmod(0o755, root)
      end
    end

    # Writes a Tenant into a shared directory, or rewrites one already there.
    def publish(root, name, manifest: "{}", body: "here", source: worker(body))
      dir = File.join(root, name)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "app.json"), manifest)
      File.write(File.join(dir, "main.rb"), source)
      dir
    end

    # A Worker answering with something the test can recognise.
    def worker(body)
      <<~RUBY
        App = ->(env) { [200, { "content-type" => "text/plain" }, ["#{body}"]] }
      RUBY
    end

    # A mount for the Tenants' database files, pointed at for the block.
    def mounting
      Dir.mktmpdir do |root|
        Workers::Host.set :databases, Workers::Databases.new(root: root)
        yield root
      end
    end
  end
end
