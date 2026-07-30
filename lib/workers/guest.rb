# frozen_string_literal: true

require "securerandom"

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

      reachable :node, :writer?, :tenant, :request_id

      attr_reader :tenant, :request_id

      def initialize(node:, tenant:)
        @node = node
        @tenant = tenant
        @request_id = SecureRandom.uuid
      end

      def node = @node.name
      def writer? = @node.writer?
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
