# frozen_string_literal: true

module Workers
  # The replicated filesystem mount the Tenants' SQLite files sit on.
  #
  # The mount holds no subdirectories, so a database is `<tenant>-<database
  # identifier>.db` at its root. An identifier carries no `-`, so the last one
  # in a filename always separates the Tenant from the identifier and no two
  # Tenants resolve to the same file.
  Databases = Data.define(:root) do
    def self.current(env = ENV)
      new(root: env.fetch("WORKERS_DB_DIR", "db"))
    end

    def open(tenant, identifier)
      Guest::Database.new(File.join(root, "#{tenant}-#{identifier}.db"))
    end
  end
end
