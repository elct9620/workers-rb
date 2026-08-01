# frozen_string_literal: true

require "sinatra/base"

module Workers
  # The Ruby process running on one Node: resolves a request to exactly one
  # Tenant and hands back what that Tenant's Worker returned, unchanged.
  class Host < Sinatra::Base
    set :app_dir, ENV.fetch("WORKERS_APP_DIR", "app")
    # Left unset, `<tenant>.<base>` reaches nothing: a Host that has not been
    # told which suffix is its own cannot read a label as a Tenant name.
    set :base_domain, ENV.fetch("WORKERS_BASE_DOMAIN", nil)
    set :node, Node.current
    set :databases, Databases.current
    set :runtime, Runtime.default

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

    # Ahead of the routing, because a body the Host will not carry is refused
    # before it is read rather than after a Tenant has been found for it.
    use BodyLimit

    # Tenants are resolved from the request, not from a route table, so every
    # method lands on the same handler.
    %i[get post put patch delete options].each do |verb|
      public_send(verb, "/*") { dispatch }
    end

    private

    def dispatch
      tenant, script_name, path = route
      halt 404 unless tenant

      request.script_name = script_name
      request.path_info = path
      tenant.call(request, node: settings.node, databases: settings.databases)
    rescue InvalidManifest => e
      # A Manifest the Host cannot act on is not a Tenant, so its endpoints
      # answer as though nothing were published there. The operator is the
      # only one who can fix it, so the reason goes to them and not outward.
      env["rack.errors"].puts(e.message)
      halt 404
    rescue BodyTooLarge
      # Nothing declared how long this body was, so the read is what found it.
      # The Worker never saw it, and the caller learns only that.
      halt 413
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

    # The Tenant this request belongs to, and the path split that goes with the
    # form that found it. The forms are tried in one order, so a request
    # answering to more than one reaches the Tenant that claimed the most
    # specific name for itself rather than whichever was looked up first.
    def route
      @claims = Registry.claims(settings.app_dir)

      claimed = lookup(@claims.tenant(request.host))
      return [ claimed, "", request.path_info ] if claimed

      under_base = lookup(subdomain)
      return [ under_base, "", request.path_info ] if under_base

      name, rest = split_path
      [ lookup(name), "/#{name}", rest ]
    end

    def lookup(name)
      return unless name

      domain = @claims.contested(name)
      raise InvalidManifest, "tenant #{name.inspect} is not routable: another Tenant declares #{domain.inspect}" if domain

      Registry.find(settings.app_dir, name, runtime: settings.runtime)
    end

    # The label the Host's own base domain leaves in front of it. A hostname
    # that is not under that domain leaves nothing, and neither does a Host
    # with no base domain configured.
    def subdomain
      return unless settings.base_domain

      suffix = ".#{settings.base_domain}"
      request.host.delete_suffix(suffix) if request.host.end_with?(suffix)
    end

    # Rack's SCRIPT_NAME / PATH_INFO convention: the segment that routed here
    # becomes the prefix, the remainder becomes the path.
    def split_path
      _, name, rest = request.path_info.split("/", 3)
      [ name.to_s, rest.nil? ? "" : "/#{rest}" ]
    end
  end
end
