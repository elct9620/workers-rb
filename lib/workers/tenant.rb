# frozen_string_literal: true

require "json"

module Workers
  # One application unit under the shared directory — a Manifest plus mruby
  # source — and the Sandbox they are loaded into.
  class Tenant
    NAME = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/
    MANIFEST = "app.json"
    DEFAULT_ENTRYPOINT = "App"

    # kobako's defaults are looser on every one of these.
    TIMEOUT = 5.0
    MEMORY_LIMIT = 16 * 1024 * 1024
    OUTPUT_LIMIT = 64 * 1024

    Loaded = Struct.new(:sandbox, :entrypoint)
    private_constant :Loaded

    REGISTRY = {}
    REGISTRY_LOCK = Mutex.new
    private_constant :REGISTRY, :REGISTRY_LOCK

    # A Tenant outlives the request that first reached it, because the
    # Sandbox it holds is what makes the second request cheaper than the
    # first.
    def self.find(root, name, guest_binary:)
      return unless name.match?(NAME)

      dir = File.join(root, name)
      return unless File.file?(File.join(dir, MANIFEST))

      REGISTRY_LOCK.synchronize { REGISTRY[dir] ||= new(dir, guest_binary: guest_binary) }
    end

    def initialize(dir, guest_binary:)
      @dir = dir
      @guest_binary = guest_binary
      @lock = Mutex.new
    end

    # Runs one invocation. The Bindings are supplied here rather than when
    # the Sandbox is built, so nothing this request touched survives into the
    # next one.
    def call(rack_request)
      loaded = current

      loaded.sandbox.run(loaded.entrypoint, Guest::Request.new(rack_request)) do |context|
        context.bind("Time", Guest::Clock.new)
        context.bind("Random", Guest::Entropy.new)
      end.value
    end

    private

    def current
      @lock.synchronize do
        stamp = fingerprint
        @loaded = nil unless @stamp == stamp
        @stamp = stamp
        @loaded ||= build
      end
    end

    # kobako seals the Service registry and snippet table at the first
    # dispatch, so a changed Tenant is rebuilt rather than amended.
    def build
      sandbox = Kobako::Sandbox.new(
        wasm_path: @guest_binary,
        timeout: TIMEOUT,
        memory_limit: MEMORY_LIMIT,
        stdout_limit: OUTPUT_LIMIT,
        stderr_limit: OUTPUT_LIMIT,
        gvl: :release
      )
      sandbox.bind("Time")
      sandbox.bind("Random")
      sources.each_with_index do |path, index|
        sandbox.preload(code: File.read(path), name: snippet_name(path, index))
      end

      Loaded.new(sandbox, entrypoint)
    end

    # kobako reports a guest backtrace against the snippet name and rejects a
    # duplicate, so the name follows the tenant's own filename and carries the
    # load position that keeps it unique.
    def snippet_name(path, index)
      token = File.basename(path, ".rb").split(/[^a-zA-Z0-9]+/).map(&:capitalize).join
      "Source#{index}#{token}"
    end

    def entrypoint
      manifest = JSON.parse(File.read(File.join(@dir, MANIFEST)))
      manifest.fetch("entrypoint", DEFAULT_ENTRYPOINT).to_sym
    end

    # Lexicographic, so a later file may reference what an earlier one
    # defined.
    def sources = Dir.glob(File.join(@dir, "*.rb")).sort

    def fingerprint
      [File.join(@dir, MANIFEST), *sources].map do |path|
        stat = File.stat(path)
        [path, stat.mtime.to_r, stat.size]
      end
    end
  end
end
