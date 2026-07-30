# frozen_string_literal: true

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

    # The request as tenant code reads it. A `Rack::Request` cannot cross the
    # boundary itself — the guest could call `#env` on it and take the whole
    # Rack environment, and the Host's configuration with it.
    class Request
      include AllowList

      reachable :request_method, :script_name, :path, :query, :headers, :body

      # Neither carries the `HTTP_` prefix the rest of the headers do.
      CONTENT_HEADERS = {
        "CONTENT_TYPE" => "content-type",
        "CONTENT_LENGTH" => "content-length"
      }.freeze

      def initialize(rack_request)
        @rack = rack_request
      end

      # Named as Rack names it. `method` is unreachable whatever a Binding
      # calls it: the guest refuses it before dispatch, because on a proxy it
      # is `Object#method` and would hand out a callable to anything.
      def request_method = @rack.request_method
      def script_name = @rack.script_name
      def path = @rack.path_info
      def query = @rack.params

      # Every field read is its own round-trip, so tenant code may reach this
      # one after something else has already consumed the input.
      def body
        input = @rack.body
        return "" if input.nil?

        input.rewind if input.respond_to?(:rewind)
        input.read.to_s
      end

      def headers
        @rack.each_header.filter_map { |key, value|
          name = header_name(key)
          [ name, value ] if name
        }.to_h
      end

      private

      def header_name(key)
        return CONTENT_HEADERS[key] if CONTENT_HEADERS.key?(key)
        return unless key.start_with?("HTTP_")

        key.delete_prefix("HTTP_").downcase.tr("_", "-")
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
