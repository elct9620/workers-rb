# frozen_string_literal: true

module Workers
  # The mruby source every Sandbox carries ahead of a Tenant's own files, so
  # tenant code reaches `Req` and `Res` at the top level.
  #
  # It runs entirely in the guest and crosses no boundary: `Req` only keeps
  # what the Request Binding already answered, and `Res` only shapes a Rack
  # triplet. A Tenant that defines either name reaches its own definition,
  # because snippets replay in load order and a Tenant's files come last.
  module RuntimeKit
    NAME = "RuntimeKit"

    SOURCE = <<~'MRUBY'
      class Req
        def initialize(request)
          @request = request
        end

        # Every field costs a round-trip to the Host, so each is read once and
        # kept for the rest of the invocation.
        def request_method
          @request_method ||= @request.request_method
        end

        def script_name
          @script_name ||= @request.script_name
        end

        def path
          @path ||= @request.path
        end

        def query
          @query ||= @request.query
        end

        def headers
          @headers ||= @request.headers
        end

        def body
          @body ||= @request.body
        end
      end

      module Res
        def self.text(body, status: 200, headers: {})
          [status, { "content-type" => "text/plain; charset=utf-8" }.merge(headers), [body.to_s]]
        end

        def self.json(data, status: 200, headers: {})
          [status, { "content-type" => "application/json" }.merge(headers), [JSON.generate(data)]]
        end

        def self.status(code, body = "")
          text(body, status: code)
        end
      end
    MRUBY
  end
end
