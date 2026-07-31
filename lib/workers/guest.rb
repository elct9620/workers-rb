# frozen_string_literal: true

require "securerandom"
require "sqlite3"

module Workers
  # The Host objects tenant code can reach. Every one of them narrows its
  # surface to a list: kobako asks `respond_to_guest?` before dispatching, so
  # a method left off the list is invisible rather than merely refused.
  module Guest
    module AllowList
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def reachable(*names)
          @reachable = names.freeze
        end

        # A class that declares nothing reaches nothing, so forgetting the
        # declaration closes the surface rather than opening it.
        def reachable?(name)
          (@reachable || []).include?(name)
        end
      end

      private

      def respond_to_guest?(name)
        self.class.reachable?(name)
      end
    end

    # Where and why this invocation is running. The Node and the Tenant are
    # the Host's facts; the request identity is minted here, so one invocation
    # reads one value however often it asks.
    class Env
      include AllowList

      reachable :node, :tenant, :request_id

      attr_reader :tenant, :request_id

      def initialize(node:, tenant:)
        @node = node
        @tenant = tenant
        @request_id = SecureRandom.uuid
      end

      def node = @node.name
    end

    # One SQLite database a Tenant declared, reachable under the constant the
    # Manifest gave it. The Host resolves the file, so tenant code names a
    # Binding rather than a path and reaches no database it did not declare.
    class Database
      include AllowList

      reachable :query, :execute

      def initialize(path, errors: nil)
        @path = path
        @errors = errors
      end

      # An Array of rows, each a Hash of column name to value.
      def query(sql, *params) = connection.execute(sql, params)

      # The rows the statement affected.
      def execute(sql, *params)
        connection.execute(sql, params)
        connection.changes
      end

      # Not reachable from the guest — the allow list omits it — so the Host
      # closes what one invocation opened without tenant code being able to.
      def close
        @connection&.close
        @connection = nil
      end

      private

      # Concurrent invocations of one Tenant each hold their own connection to
      # the same file, so a writer meeting another's lock waits rather than
      # failing. The wait outlasts no request: the invocation's own wall clock
      # is what ends it.
      BUSY_TIMEOUT = 5_000
      private_constant :BUSY_TIMEOUT

      # Opened on first use, so a Tenant that declares a database it never
      # touches pays nothing, and a database that cannot be opened reaches
      # tenant code as a failure it may rescue rather than one that precedes
      # the invocation.
      def connection
        @connection ||= SQLite3::Database.new(@path, results_as_hash: true)
                                         .tap { |db| db.busy_timeout = BUSY_TIMEOUT }
      rescue SQLite3::Exception => e
        # Reaching the database at all is the Host's side of the contract, so
        # this failure is the operator's to see — a statement the Tenant got
        # wrong is not, and never reaches here. What the guest gets is
        # unchanged either way.
        @errors&.puts("cannot open #{@path}: #{e.message}")
        raise
      end
    end

    # The guest's mruby build defines no `Time`, so the Host supplies one.
    class Clock
      include AllowList

      reachable :now

      def now = ::Time.now.to_f
    end

    # The guest's mruby build defines no `Random` either, and a sandbox that
    # cannot draw one has no source of entropy at all.
    class Entropy
      include AllowList

      reachable :rand

      def rand(limit = nil) = limit ? Kernel.rand(limit) : Kernel.rand
    end
  end
end
