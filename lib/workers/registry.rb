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

    # The domains claimed under one shared directory, and what the directory
    # looked like when they were read.
    Claims = Struct.new(:stamp, :names, :contests) do
      # The Tenant that declared this domain for itself, if exactly one did.
      def tenant(domain) = names[domain]

      # The domain this Tenant declared that another Tenant declared too. The
      # Host has no way to pick between them, and picking wrong would hand one
      # Tenant's traffic to another Tenant's code.
      def contested(name) = contests[name]
    end

    TENANTS = {}
    # Keyed by shared directory, of which a Host has one for its life, so this
    # holds a single entry however long it runs.
    CLAIMS = {}
    LOCK = Mutex.new
    private_constant :TENANTS, :CLAIMS, :LOCK

    def self.find(root, name, runtime:)
      return unless name.match?(NAME)

      dir = File.join(root, name)
      manifest = File.join(dir, MANIFEST)
      return absent(root, dir) unless File.file?(manifest)

      LOCK.synchronize { published(dir, manifest, runtime) }
    rescue InvalidManifest => e
      # Only the Registry knows which Tenant the Manifest belonged to, and the
      # operator reading the record is the one who has to find the file.
      raise InvalidManifest, "tenant #{name.inspect} is not routable: #{e.message}"
    end

    # What every Tenant under the directory declared for itself. No single
    # Tenant could be asked whether it claimed a domain, so answering means
    # reading all of them — which is what a domain costs over a name.
    #
    # Reread whenever any Manifest is added, rewritten, or removed, so the
    # shared directory governs what a domain reaches.
    def self.claims(root)
      stamp = manifests(root)
      cached = LOCK.synchronize { CLAIMS[root] }
      return cached if cached&.stamp == stamp

      # Read outside the lock: every request pays the walk, and one Host has
      # one shared directory to disagree about.
      names, contests = scan(root)
      LOCK.synchronize { CLAIMS[root] = Claims.new(stamp, names, contests) }
    end

    # Reached only when no Manifest answers, so the two questions the Host
    # cannot otherwise tell apart are asked where the answer matters and
    # nowhere else: a directory it cannot read is not one where nothing was
    # published, and a Sandbox cached from when it could be read must not
    # stand in for one.
    def self.absent(root, dir)
      raise SourceUnreadable, root unless readable?(root)

      forget(dir)
    end
    private_class_method :absent

    def self.readable?(root) = File.readable?(root) && File.executable?(root)
    private_class_method :readable?

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

    # The domains one Tenant declared alone, and the Tenants left contesting
    # one another for the rest.
    def self.scan(root)
      names = {}
      contests = {}

      declared(root).each do |domain, claimants|
        if claimants.one?
          names[domain] = claimants.first
        else
          claimants.each { |name| contests[name] = domain }
        end
      end

      [ names, contests ]
    end
    private_class_method :scan

    # A Manifest the Host cannot act on declares nothing rather than stopping
    # the read: one Tenant's mistake is not the other Tenants' to pay for.
    def self.declared(root)
      manifest_paths(root).each_with_object({}) do |path, claimants|
        name = File.basename(File.dirname(path))
        next unless name.match?(NAME)

        domain = parse(path).domain
        (claimants[domain] ||= []) << name if domain
      rescue InvalidManifest, SourceUnreadable
        next
      end
    end
    private_class_method :declared

    # A Manifest that vanishes between the walk and the stat simply drops out,
    # which reads as a change.
    def self.manifests(root)
      manifest_paths(root).filter_map do |path|
        [ path, *stamp(path) ]
      rescue SourceUnreadable
        nil
      end
    end
    private_class_method :manifests

    # An unreadable shared directory yields nothing rather than raising here —
    # telling that apart from a directory holding no Tenants is `absent`'s to
    # do, once a request has named the Tenant it expected to find. Asked before
    # the walk rather than discovered during it, so an outage the operator
    # already hears about once does not also warn on every entry.
    def self.manifest_paths(root)
      return [] unless readable?(root)

      Dir.glob(File.join(root, "*", MANIFEST)).sort
    end
    private_class_method :manifest_paths

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
