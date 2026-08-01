# frozen_string_literal: true

require "socket"

# Servers that fail the way one across a network does, which a refused
# connection cannot stand in for: one that takes the connection and then says
# nothing, one that answers every request by declining, and one that ends a
# connection the Host is still holding.
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

    # Has to be told a database exists before it will answer for one, and ends
    # the connection it said so on rather than serving anything else down it.
    # A Host that keeps its connections meets this the moment a Tenant's first
    # statement arrives, and a server that closed politely would not prove it:
    # the client sees that one coming.
    def letting_go(answer)
      lock = Mutex.new
      served = 0
      serving do |socket|
        answered = false
        while consume(socket)
          break reset(socket) if answered

          answered = true
          socket.print(lock.synchronize { (served += 1) == 1 } ? refusal : ok(answer))
        end
      end
    end

    # Answers, and says nothing worth reading. The side of the server the Host
    # talks to on its own errands rather than a Tenant's.
    def obliging
      serving { |socket| socket.print(ok("")) while consume(socket) }
    end

    private

    # Reads a whole request, so that closing on one only half-read is not a
    # broken pipe standing in for what is being tested. False once the client
    # has finished with the connection.
    def consume(socket)
      line = socket.gets or return false
      length = 0
      until line.nil? || line == "\r\n"
        length = line.split(":").last.to_i if line.downcase.start_with?("content-length:")
        line = socket.gets
      end
      socket.read(length)
      true
    end

    def ok(body) = message(200, "OK", body)

    def refusal = message(404, "Not Found", %({"error":"no such database"}))

    def message(status, reason, body)
      "HTTP/1.1 #{status} #{reason}\r\ncontent-type: application/json\r\n" \
        "content-length: #{body.bytesize}\r\n\r\n#{body}"
    end

    # Torn down rather than closed: an orderly close reaches the client as an
    # end of stream it can see before it sends, which is the case that asks
    # nothing of the Host.
    def reset(socket)
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [ 1, 0 ].pack("ii"))
      socket.close
    end

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
