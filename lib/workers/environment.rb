# frozen_string_literal: true

module Workers
  # The request as tenant code reads it: one Hash the Host composes and hands
  # to the Worker whole.
  #
  # A `Rack::Request` cannot cross the boundary itself — the guest could call
  # `#env` on it and take the whole Rack environment, and the Host's
  # configuration with it. Composing the fields here leaves what the Host
  # withheld with no name in the guest at all, rather than a name that is
  # refused.
  module Environment
    # Neither carries the `HTTP_` prefix the rest of the headers do.
    CONTENT_HEADERS = {
      "CONTENT_TYPE" => "content-type",
      "CONTENT_LENGTH" => "content-length"
    }.freeze
    private_constant :CONTENT_HEADERS

    # Named as Rack names them, and read in one pass: the Worker holds the
    # whole request before it runs, so nothing it asks for reaches back here.
    def self.for(rack_request)
      {
        "request_method" => rack_request.request_method,
        "script_name" => rack_request.script_name,
        "path" => rack_request.path_info,
        "query" => rack_request.GET,
        "headers" => headers(rack_request),
        "body" => body(rack_request)
      }
    end

    # `BodyLimit` refuses on the length a request declares, and a request that
    # declared none reaches here anyway. One byte past the limit is what says
    # the body ran past it, so the Host holds no more than it will carry.
    def self.body(rack_request)
      input = rack_request.body
      return "" if input.nil?

      input.rewind if input.respond_to?(:rewind)
      read = input.read(BodyLimit::BYTES + 1).to_s
      raise BodyTooLarge if read.bytesize > BodyLimit::BYTES

      read
    end
    private_class_method :body

    def self.headers(rack_request)
      rack_request.each_header.filter_map { |key, value|
        name = header_name(key)
        [ name, value ] if name
      }.to_h
    end
    private_class_method :headers

    def self.header_name(key)
      return CONTENT_HEADERS[key] if CONTENT_HEADERS.key?(key)
      return unless key.start_with?("HTTP_")

      key.delete_prefix("HTTP_").downcase.tr("_", "-")
    end
    private_class_method :header_name
  end
end
