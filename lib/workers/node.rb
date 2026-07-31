# frozen_string_literal: true

require "socket"

module Workers
  # The cluster node this Host runs on, as tenant code reads it through `Env`.
  #
  # The hostname the operating system reports is what an operator can
  # recognise a Node by, so it is what the Host answers with rather than a
  # name of the Host's own.
  Node = Data.define(:name) do
    def self.current = new(name: Socket.gethostname)
  end
end
