# frozen_string_literal: true

module Workers
  # One application unit under the shared directory — a Manifest plus mruby
  # source — and the Sandbox they are loaded into.
  class Tenant
    def initialize(dir, manifest, runtime:)
      @dir = dir
      @name = File.basename(dir)
      @manifest = manifest
      @runtime = runtime
      @lock = Mutex.new
    end

    # Runs one invocation. The Bindings are supplied here rather than when the
    # Sandbox is built, so nothing this request touched survives into the next
    # one.
    def call(rack_request, node:, databases:)
      sandbox = current
      errors = rack_request.env["rack.errors"]
      supplied = @manifest.databases.to_h { |constant, identifier|
        [ constant, databases.for(@name, identifier, errors: errors) ]
      }

      execution = sandbox.run(@manifest.entrypoint.to_sym, Environment.for(rack_request)) do |context|
        context.bind("Env", Guest::Env.new(node: node, tenant: @name))
        context.bind("Time", Guest::Clock.new)
        context.bind("Random", Guest::Entropy.new)
        supplied.each { |constant, database| context.bind(constant, database) }
      end

      record(execution, errors)
      ensure_triplet(execution.value)
    rescue Kobako::CarriesExecution => e
      # The invocation that failed is the one whose output is worth most, and
      # the one that returns no value to read it off. kobako hands the same
      # captures out on the error, so the rescue says what the return would
      # have.
      record(e.execution, errors)
      discard if e.is_a?(Kobako::TrapError)
      raise
    end

    private

    # What the Worker wrote, where the operator reads. A Tenant has no other
    # way to say anything that is not a response, and a line nobody can tell
    # the Tenant or the stream of is a line nobody can act on — so every one
    # of them carries both.
    def record(execution, errors)
      return unless execution && errors

      say(errors, "out", execution.stdout, execution.stdout_truncated?)
      say(errors, "err", execution.stderr, execution.stderr_truncated?)
    end

    def say(errors, stream, wrote, clipped)
      wrote.each_line { |line| errors.puts("#{@name} #{stream}: #{line.chomp}") }
      errors.puts("#{@name} #{stream}: clipped at the limit") if clipped
    end

    def current
      @lock.synchronize do
        stamp = fingerprint
        @sandbox = nil unless @stamp == stamp
        @stamp = stamp
        @sandbox ||= build
      end
    end

    # A trap leaves the Sandbox unusable, so the next request builds a new one
    # rather than dispatching into it.
    def discard
      @lock.synchronize { @sandbox = @stamp = nil }
    end

    # kobako seals the Service registry and snippet table at the first
    # dispatch, so changed source is rebuilt rather than amended.
    def build
      sandbox = @runtime.sandbox
      sandbox.bind("Env")
      sandbox.bind("Time")
      sandbox.bind("Random")
      # Declared here and supplied per invocation, so a constant the Manifest
      # left out is a `NameError` in the guest rather than a Binding that
      # happens to be empty.
      @manifest.databases.each_key { |constant| sandbox.bind(constant) }
      sandbox.preload(code: RuntimeKit::SOURCE, name: RuntimeKit::NAME)
      sources.each_with_index do |path, index|
        sandbox.preload(code: read(path), name: snippet_name(path, index))
      end

      sandbox
    end

    def read(path)
      File.read(path)
    rescue SystemCallError
      raise SourceUnreadable, path
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
      sources.filter_map do |path|
        stat = File.stat(path)
        [ path, stat.mtime.to_r, stat.size ]
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
