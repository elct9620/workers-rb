# frozen_string_literal: true

module Workers
  # Where this Host reaches the Tenants' SQLite databases.
  #
  # A database is named for the Tenant and the identifier together, and an
  # identifier carries no `-`, so the last one in a name always separates the
  # two and no two Tenants resolve to the same database.
  Databases = Data.define(:root) do
    def self.current(env = ENV)
      new(root: env.fetch("WORKERS_DB_DIR", "db"))
    end

    # The Binding for one Tenant's database. Nothing is opened here — the
    # database is reached on the first statement run against it.
    def for(tenant, identifier, errors: nil)
      Guest::Database.new(File.join(root, "#{tenant}-#{identifier}.db"), errors: errors)
    end
  end
end
