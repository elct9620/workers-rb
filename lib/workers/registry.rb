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
    MANIFEST = "app.json"

    CACHED = 64

    # What the Manifest was when this Tenant was made, so a rewritten one is
    # recognised as a different Tenant rather than the same one amended.
    Published = Struct.new(:stamp, :tenant)
    private_constant :Published

    TENANTS = {}
    LOCK = Mutex.new
    private_constant :TENANTS, :LOCK

    def self.find(root, name, runtime:)
      return unless name.match?(NAME)

      dir = File.join(root, name)
      manifest = File.join(dir, MANIFEST)
      return absent(root, dir) unless File.file?(manifest)

      LOCK.synchronize { published(dir, manifest, runtime) }
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

    # The Tenant this Manifest published. A Manifest decides what its Sandbox
    # is built with, so a rewritten one makes a new Tenant rather than amending
    # the one already cached.
    def self.published(dir, manifest, runtime)
      key = [ dir, runtime ]
      stamp = stamp(manifest)
      entry = TENANTS.delete(key)
      entry = Published.new(stamp, Tenant.new(dir, parse(manifest), runtime: runtime)) unless entry&.stamp == stamp

      remember(key, entry)
    end
    private_class_method :published

    # Ruby's Hash keeps insertion order, so re-inserting on every reach leaves
    # the oldest entry the least recently reached one.
    def self.remember(key, entry)
      TENANTS[key] = entry
      TENANTS.shift while TENANTS.size > CACHED
      entry.tenant
    end
    private_class_method :remember

    def self.stamp(path)
      stat = File.stat(path)
      [ stat.mtime.to_r, stat.size ]
    rescue SystemCallError
      raise SourceUnreadable, path
    end
    private_class_method :stamp

    def self.parse(path)
      Manifest.parse(File.read(path))
    rescue SystemCallError
      raise SourceUnreadable, path
    end
    private_class_method :parse
  end
end
