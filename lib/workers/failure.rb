# frozen_string_literal: true

module Workers
  # A Manifest the Host cannot read as one. The Tenant is not routable.
  class InvalidManifest < StandardError; end

  # A Tenant's own files the Host cannot read.
  class SourceUnreadable < StandardError; end

  # A Worker's return value that is not a Rack response triplet.
  class InvalidResponse < StandardError; end

  # A Binding that did not answer with what was asked of it. A statement the
  # database refused carries what it said; a database the Host could not reach
  # carries nothing but that, because where the Host looked is the operator's
  # to read and not the Tenant's. Either way the Tenant may rescue it, and
  # left unrescued either ends the request as a binding failure.
  class DatabaseError < StandardError; end

  # The category a failed invocation answers with. kobako's errors say what
  # broke inside the Sandbox; a Failure says it in the Tenant's own terms and
  # carries the status that goes with it — 503 where the Sandbox was cut short
  # and a retry may land differently, 500 where the Tenant's own code decided
  # the outcome.
  class Failure
    # Read most-specific first: kobako's classes nest, and a TimeoutError is a
    # TrapError too.
    TABLE = [
      [ Kobako::UndefinedEntrypointError, "undefined_entrypoint", 500 ],
      [ Kobako::TimeoutError, "timeout", 503 ],
      [ Kobako::MemoryLimitError, "memory_limit", 503 ],
      [ Kobako::ServiceError, "binding_failure", 500 ],
      [ Kobako::SandboxError, "tenant_exception", 500 ],
      [ Kobako::TrapError, "runtime_corruption", 503 ],
      [ InvalidResponse, "invalid_response", 500 ]
    ].freeze
    private_constant :TABLE

    # Source that never compiled arrives as an ordinary sandbox error; the
    # guest class is what separates it from a Worker's own exception.
    COMPILING = %w[SyntaxError ScriptError].freeze
    private_constant :COMPILING

    # The Failure for +error+, or nil when the Host has no class for it — an
    # error it cannot name is not one to describe to a Tenant.
    def self.for(error)
      return new("compile_failure", 500) if compiling?(error)

      row = TABLE.find { |klass, _name, _status| error.is_a?(klass) }
      new(row[1], row[2]) if row
    end

    def self.compiling?(error)
      error.is_a?(Kobako::SandboxError) && COMPILING.include?(error.klass)
    end
    private_class_method :compiling?

    attr_reader :name, :status

    def initialize(name, status)
      @name = name
      @status = status
    end

    # The failure class and nothing else: no Host environment variable, no
    # filesystem path, no internal address.
    def to_response
      [ status, { "content-type" => "text/plain; charset=utf-8" }, [ "#{name}\n" ] ]
    end
  end
end
