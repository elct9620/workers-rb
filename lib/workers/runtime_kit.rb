# frozen_string_literal: true

module Workers
  # The mruby source every Sandbox carries ahead of a Tenant's own files, so
  # tenant code reaches `Request` and `Response` at the top level.
  #
  # It runs entirely in the guest and crosses no boundary: `Request` names the
  # keys of a Hash the Worker already holds, and `Response` shapes a Rack
  # triplet. A Tenant that defines either name reaches its own definition,
  # because snippets replay in load order and a Tenant's files come last.
  module RuntimeKit
    NAME = "RuntimeKit"

    SOURCE = <<~'MRUBY'
      class Request
        def initialize(env)
          @env = env
        end

        def request_method
          @env["request_method"]
        end

        def script_name
          @env["script_name"]
        end

        def path
          @env["path"]
        end

        def query
          @env["query"]
        end

        def headers
          @env["headers"]
        end

        def body
          @env["body"]
        end
      end

      module Response
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
