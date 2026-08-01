# frozen_string_literal: true

require "socket"

# Servers that fail the way a database in trouble does, which a refused
# connection cannot stand in for: one that takes the connection and then says
# nothing, and one that answers every request by declining.
#
# A refusal is instant, so it proves nothing about what the Host does while
# it waits. These are what put a wait in front of it.
module Unresponsive
  class << self
    def silent = serving { sleep }

    def declining(status)
      serving do |socket|
        socket.gets
        socket.print("HTTP/1.1 #{status} Declined\r\ncontent-length: 0\r\n\r\n")
        socket.close
      end
    end

    private

    # Listens for the rest of the run. Closing it is what ends the accept
    # loop, and the loop says so rather than reporting it as a failure.
    def serving(&accepted)
      server = TCPServer.new("127.0.0.1", 0)
      Thread.new do
        loop { Thread.new(server.accept, &accepted) }
      rescue IOError
        nil
      end
      at_exit { server.close }

      server.addr[1]
    end
  end
end
