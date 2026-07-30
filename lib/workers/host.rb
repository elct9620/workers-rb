# frozen_string_literal: true

require "sinatra/base"

module Workers
  # The Ruby process running on one Node: resolves a request to exactly one
  # Tenant and hands back what that Tenant's Worker returned, unchanged.
  class Host < Sinatra::Base
    set :app_dir, ENV.fetch("WORKERS_APP_DIR", "app")
    set :node, Node.current
    set :databases, Databases.current
    set :runtime, Runtime.default(
      guest_binary: ENV.fetch("WORKERS_GUEST_BINARY", Workers.default_guest_binary)
    )

    # A Tenant reaches the cluster under a domain it declares for itself, so
    # the set of hostnames the Host answers to is not knowable in advance and
    # cannot be an allow list. What a Host header may select is a Tenant, and
    # nothing more.
    set :host_authorization, { permitted_hosts: [] }

    # A Tenant's failure is one request's outcome, never the Host's to
    # propagate, and what reaches the caller carries no trace of where the
    # Host keeps its files. The operator still gets the backtrace in the log.
    set :raise_errors, false
    set :show_exceptions, false

    # Tenants are resolved from the request, not from a route table, so every
    # method lands on the same handler.
    %i[get post put patch delete options].each do |verb|
      public_send(verb, "/*") { dispatch }
    end

    private

    def dispatch
      name, rest = split_path
      tenant = Tenant.find(settings.app_dir, name, runtime: settings.runtime)
      halt 404 unless tenant

      request.script_name = "/#{name}"
      request.path_info = rest
      tenant.call(request, node: settings.node, databases: settings.databases)
    rescue InvalidManifest => e
      # A Manifest the Host cannot act on is not a Tenant, so its endpoints
      # answer as though nothing were published there. The operator is the
      # only one who can fix it, so the reason goes to them and not outward.
      env["rack.errors"].puts("tenant #{name.inspect} is not routable: #{e.message}")
      halt 404
    rescue SourceUnreadable => e
      # The Tenant published nothing wrong; this Host cannot reach what it
      # published. Only the operator can act on that, and only if told.
      env["rack.errors"].puts("cannot read #{e.message}")
      halt 503
    rescue StandardError => e
      failure = Failure.for(e)
      raise unless failure

      failure.to_response
    end

    # Rack's SCRIPT_NAME / PATH_INFO convention: the segment that routed here
    # becomes the prefix, the remainder becomes the path.
    def split_path
      _, name, rest = request.path_info.split("/", 3)
      [ name.to_s, rest.nil? ? "" : "/#{rest}" ]
    end
  end
end
