# frozen_string_literal: true

module Workers
  # The shared directory as the Host reads it: which of the directories under
  # it constitute Tenants, and which Tenant a name reaches.
  #
  # A Tenant outlives the request that first reached it, because the Sandbox
  # it holds is what makes the second request cheaper than the first. The
  # Registry keeps a bounded number of them, least recently reached first out:
  # a shared directory that has held many Tenants over a Host's life would
  # otherwise accumulate every Sandbox it ever built.
  class Registry
    NAME = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

    CACHED = 64

    TENANTS = {}
    LOCK = Mutex.new
    private_constant :TENANTS, :LOCK

    def self.find(root, name, runtime:)
      return unless name.match?(NAME)

      dir = File.join(root, name)
      return absent(root, dir) unless File.file?(File.join(dir, Tenant::MANIFEST))

      LOCK.synchronize { remember([ dir, runtime ]) { Tenant.new(dir, runtime: runtime) } }
    end

    # Reached only when no Manifest answers, so the two questions the Host
    # cannot otherwise tell apart are asked where the answer matters and
    # nowhere else: a directory it cannot read is not one where nothing was
    # published, and a Sandbox cached from when it could be read must not
    # stand in for one.
    def self.absent(root, dir)
      raise SourceUnreadable, root unless File.readable?(root) && File.executable?(root)

      forget(dir)
    end
    private_class_method :absent

    def self.forget(dir)
      LOCK.synchronize { TENANTS.delete_if { |(cached, _), _| cached == dir } }
      nil
    end
    private_class_method :forget

    # Ruby's Hash keeps insertion order, so re-inserting on every reach leaves
    # the oldest entry the least recently reached one.
    def self.remember(key)
      tenant = TENANTS.delete(key) || yield
      TENANTS[key] = tenant
      TENANTS.shift while TENANTS.size > CACHED
      tenant
    end
    private_class_method :remember
  end
end
