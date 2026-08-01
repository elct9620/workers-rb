# frozen_string_literal: true

module Workers
  # How many statements this Host has in flight at once. Enough for every
  # thread that could be serving, or a thread waits on a connection rather
  # than on the database; and few enough that every Node together stays under
  # what the server will hold open.
  DEFAULT_DB_POOL = 5

  # Where this Host reaches the Tenants' databases, and where it has one made
  # that a Manifest declared but nothing created yet.
  #
  # A database is named for the Tenant and the identifier together, and an
  # identifier carries no `-`, so the last one in a name always separates the
  # two and no two Tenants resolve to the same database.
  Databases = Data.define(:url, :admin_url, :pool) do
    # Stated only where it differs, so what an operator has to decide stays
    # the two addresses.
    def initialize(url:, admin_url:, pool: DEFAULT_DB_POOL) = super

    def self.current(env = ENV)
      new(url: env.fetch("WORKERS_DB_URL", "http://127.0.0.1:8080"),
          admin_url: env.fetch("WORKERS_DB_ADMIN_URL", "http://127.0.0.1:8081"),
          pool: Integer(env.fetch("WORKERS_DB_POOL", DEFAULT_DB_POOL)))
    end

    # The Binding for one Tenant's database. Nothing is reached here — the
    # database answers the first statement run against it.
    def for(tenant, identifier, errors: nil)
      Guest::Database.new(
        Hrana.new(url: url, admin_url: admin_url, namespace: "#{tenant}-#{identifier}",
                  pool: pool, errors: errors)
      )
    end
  end
end
