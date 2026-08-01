# frozen_string_literal: true

module Workers
  # What one request body is allowed to cost this Host, refused on the length
  # the request declares.
  #
  # It sits ahead of everything else because the HTTP layer reads a form body
  # on its own account before the Host is asked anything, and a caller names
  # the content type. Refusing here is what keeps that read from happening —
  # a check the Host made later would already be holding what it refused.
  class BodyLimit
    # The guest's memory limit bounds what a Worker holds. The caller is not
    # the Tenant that limit was drawn around, so this bounds the other side.
    #
    # It also stays under the largest String the guest's mruby build will
    # hold: a body the Sandbox cannot be handed is one the caller would get
    # a corrupted runtime for rather than an answer.
    BYTES = 512 * 1024

    def initialize(app)
      @app = app
    end

    def call(env)
      return refused if env["CONTENT_LENGTH"].to_i > BYTES

      @app.call(env)
    end

    private

    # The status and nothing else: a caller that sent too much learns that,
    # and the Host is the only side that could act on knowing more.
    def refused = [ 413, {}, [] ]
  end
end
