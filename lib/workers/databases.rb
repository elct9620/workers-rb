# frozen_string_literal: true

module Workers
  # Where this Host reaches the Tenants' databases, and where it has one made
  # that a Manifest declared but nothing created yet.
  #
  # A database is named for the Tenant and the identifier together, and an
  # identifier carries no `-`, so the last one in a name always separates the
  # two and no two Tenants resolve to the same database.
  Databases = Data.define(:url, :admin_url) do
    def self.current(env = ENV)
      new(url: env.fetch("WORKERS_DB_URL", "http://127.0.0.1:8080"),
          admin_url: env.fetch("WORKERS_DB_ADMIN_URL", "http://127.0.0.1:8081"))
    end

    # The Binding for one Tenant's database. Nothing is reached here — the
    # database answers the first statement run against it.
    def for(tenant, identifier, errors: nil)
      Guest::Database.new(
        Hrana.new(url: url, admin_url: admin_url, namespace: "#{tenant}-#{identifier}", errors: errors)
      )
    end
  end
end
