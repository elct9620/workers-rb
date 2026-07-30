# frozen_string_literal: true

module Workers
  # One application unit under the shared directory — a Manifest plus mruby
  # source — and the Sandbox they are loaded into.
  class Tenant
    NAME = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
    MANIFEST = "app.json"

    Loaded = Struct.new(:sandbox, :entrypoint, :databases)
    private_constant :Loaded

    REGISTRY = {}
    REGISTRY_LOCK = Mutex.new
    private_constant :REGISTRY, :REGISTRY_LOCK

    # A Tenant outlives the request that first reached it, because the Sandbox
    # it holds is what makes the second request cheaper than the first. One
    # that no longer exists is forgotten instead, so its Sandbox goes with it.
    def self.find(root, name, runtime:)
      # A shared directory the Host cannot read is not one where nothing was
      # published, so the question of which Tenant lives here has no answer
      # yet — and a Sandbox cached from when it could be read must not stand
      # in for one.
      raise SourceUnreadable unless File.readable?(root) && File.executable?(root)
      return unless name.match?(NAME)

      dir = File.join(root, name)
      return forget(dir) unless File.file?(File.join(dir, MANIFEST))

      REGISTRY_LOCK.synchronize { REGISTRY[[ dir, runtime ]] ||= new(dir, runtime: runtime) }
    end

    def self.forget(dir)
      REGISTRY_LOCK.synchronize { REGISTRY.delete_if { |(cached, _), _| cached == dir } }
      nil
    end
    private_class_method :forget

    def initialize(dir, runtime:)
      @dir = dir
      @name = File.basename(dir)
      @runtime = runtime
      @lock = Mutex.new
    end

    # Runs one invocation. The Bindings are supplied here rather than when the
    # Sandbox is built, so nothing this request touched survives into the next
    # one.
    def call(rack_request, node:, databases:)
      loaded = current
      supplied = loaded.databases.to_h { |constant, identifier|
        [ constant, databases.open(@name, identifier) ]
      }

      triplet = loaded.sandbox.run(loaded.entrypoint, Environment.for(rack_request)) do |context|
        context.bind("Env", Guest::Env.new(node: node, tenant: @name))
        context.bind("Time", Guest::Clock.new)
        context.bind("Random", Guest::Entropy.new)
        supplied.each { |constant, database| context.bind(constant, database) }
      end.value

      ensure_triplet(triplet)
    rescue Kobako::TrapError
      discard
      raise
    ensure
      supplied&.each_value(&:close)
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

    # A trap leaves the Sandbox unusable, so the next request builds a new one
    # rather than dispatching into it.
    def discard
      @lock.synchronize { @loaded = @stamp = nil }
    end

    # kobako seals the Service registry and snippet table at the first
    # dispatch, so a changed Tenant is rebuilt rather than amended.
    def build
      manifest = Manifest.parse(read(File.join(@dir, MANIFEST)))
      sandbox = @runtime.sandbox
      sandbox.bind("Env")
      sandbox.bind("Time")
      sandbox.bind("Random")
      # Declared here and supplied per invocation, so a constant the Manifest
      # left out is a `NameError` in the guest rather than a Binding that
      # happens to be empty.
      manifest.databases.each_key { |constant| sandbox.bind(constant) }
      sandbox.preload(code: RuntimeKit::SOURCE, name: RuntimeKit::NAME)
      sources.each_with_index do |path, index|
        sandbox.preload(code: read(path), name: snippet_name(path, index))
      end

      Loaded.new(sandbox, manifest.entrypoint.to_sym, manifest.databases)
    end

    def read(path)
      File.read(path)
    rescue SystemCallError
      raise SourceUnreadable
    end

    # The Worker's contract, checked before the triplet reaches the HTTP layer.
    def ensure_triplet(value)
      status, headers, body = value if value.is_a?(Array) && value.size == 3
      raise InvalidResponse unless status.is_a?(Integer)
      raise InvalidResponse unless headers.is_a?(Hash) &&
                                   headers.all? { |key, item| key.is_a?(String) && item.is_a?(String) }
      raise InvalidResponse unless body.is_a?(Array) && body.all?(String)

      value
    end

    # kobako reports a guest backtrace against the snippet name and rejects a
    # duplicate, so the name follows the tenant's own filename and carries the
    # load position that keeps it unique.
    def snippet_name(path, index)
      token = File.basename(path, ".rb").split(/[^a-zA-Z0-9]+/).map(&:capitalize).join
      "Source#{index}#{token}"
    end

    # Lexicographic, so a later file may reference what an earlier one defined.
    def sources = Dir.glob(File.join(@dir, "*.rb")).sort

    # A file that vanishes between the glob and the stat simply drops out,
    # which reads as a change and rebuilds.
    def fingerprint
      [ File.join(@dir, MANIFEST), *sources ].filter_map do |path|
        stat = File.stat(path)
        [ path, stat.mtime.to_r, stat.size ]
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
