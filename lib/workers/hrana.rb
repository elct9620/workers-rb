# frozen_string_literal: true

require "connection_pool"
require "json"
require "net/http"
require "stoplight"
require "uri"

module Workers
  # One Tenant's database, as the Host reaches it over the network.
  #
  # A statement travels as its own request and closes the stream it opened, so
  # an invocation leaves nothing on the server for the next one to find. Which
  # database a request means travels in the Host header, where the server
  # reads it, so the Host names a database rather than routing to one.
  class Hrana
    # The endpoint both this server and Turso's own speak, so what the Host
    # is written against outlives either of them.
    PIPELINE = "/v2/pipeline"
    private_constant :PIPELINE

    # A statement has to give up before the invocation waiting on it does.
    # Given the same bound, the invocation's own clock runs out first and the
    # Worker is cut short instead of being handed a failure it could rescue —
    # so this stays under `Runtime`'s limit by enough for a Worker to answer.
    TIMEOUT = 2
    private_constant :TIMEOUT

    # The database answered, and what it said was that it will not do this
    # now. An operator told "cannot reach" would go looking at the network
    # rather than at how much is being asked of it.
    TOO_MANY = "429"
    private_constant :TOO_MANY

    # One pool per address, for the life of the Host. A Binding lasts one
    # invocation, so anything held per Binding would be opened and dropped
    # once per statement — which is what this exists to stop.
    POOLS = {}
    LOCK = Mutex.new
    private_constant :POOLS, :LOCK

    def initialize(url:, admin_url:, namespace:, pool: 5, cool_off: 60, errors: nil)
      @url = URI(url)
      @admin_url = URI(admin_url)
      @namespace = namespace
      @pool = pool
      @cool_off = cool_off
      @errors = errors
    end

    # An Array of rows, each a Hash of column name to value.
    def query(sql, params)
      result = run(sql, params)
      names = result.fetch("cols").map { |col| col.fetch("name") }
      result.fetch("rows").map { |row| names.zip(row.map { |value| decode(value) }).to_h }
    end

    # The rows the statement affected.
    def execute(sql, params) = run(sql, params).fetch("affected_row_count")

    private

    def run(sql, params)
      body = {
        "baton" => nil,
        "requests" => [
          { "type" => "execute", "stmt" => { "sql" => sql, "args" => params.map { |param| encode(param) } } },
          { "type" => "close" }
        ]
      }

      answered(pipeline(body))
    end

    # A database the Manifest declared exists by the time it is supplied, so a
    # server that has not heard of it is told once and asked again.
    def pipeline(body)
      answer = post(@url, PIPELINE, body)
      return answer unless answer.code == "404"

      create
      post(@url, PIPELINE, body)
    end

    # Another invocation may have created it first, which answers as a refusal
    # and leaves exactly what was wanted.
    def create = post(@admin_url, "/v1/namespaces/#{@namespace}/create", {})

    def post(address, path, body)
      request = Net::HTTP::Post.new(path, "content-type" => "application/json")
      # The server reads the first label as the database's name, so this is
      # the namespace at the server rather than a hostname anything resolves.
      request["Host"] = "#{@namespace}.#{@url.host}"
      request.body = JSON.generate(body)

      # Reused rather than opened per statement: a Host that opened one every
      # time runs out of local ports long before the database runs out of
      # capacity. Whether the connection it is handed is still good is
      # Net::HTTP's to decide — it reconnects on a socket the server closed,
      # on one idle past its keep-alive, and on one left at EOF.
      light.run { pool(address).with { |http| http.request(request) } }
    rescue Stoplight::Error::RedLight
      # Already known to be unreachable, and already said so. Waiting to find
      # out again is what would cost this request and the database both.
      raise DatabaseError, "the database is unavailable"
    rescue SystemCallError, IOError, Timeout::Error, ConnectionPool::TimeoutError => e
      failed("cannot reach #{where}: #{e.message}")
    end

    # Per database, so one Tenant's outage is not another's. What a statement
    # the database refused did is decided after this and outside it, so
    # neither a Tenant's own mistake nor a database declining more at once
    # counts towards giving up on it.
    def light = Stoplight("database:#{@namespace}", cool_off_time: @cool_off)

    # Checking out blocks while every connection is busy, which is what keeps
    # one Host from asking more of the database at once than it said it would.
    def pool(address)
      LOCK.synchronize do
        POOLS["#{address.host}:#{address.port}"] ||= ConnectionPool.new(size: @pool, timeout: TIMEOUT) {
          Net::HTTP.new(address.host, address.port).tap do |http|
            http.open_timeout = http.read_timeout = TIMEOUT
            http.start
          end
        }
      end
    end

    # Reaching the database at all is the Host's side of the contract, so a
    # failure there is the operator's to see. What the statement itself did is
    # the Tenant's, and never reaches here.
    def answered(response)
      declined if response.code == TOO_MANY
      failed("#{where} answered #{response.code}") unless response.is_a?(Net::HTTPSuccess)

      statement = JSON.parse(response.body).fetch("results").first.to_h
      raise DatabaseError, statement.dig("error", "message").to_s if statement.fetch("type") == "error"

      statement.fetch("response").fetch("result")
    rescue JSON::ParserError, KeyError
      failed("#{where} answered nothing this Host could read")
    end

    # What went wrong goes where the operator reads and no further: a Tenant
    # that rescues this learns that its database is unavailable and nothing
    # about where the Host was looking for it or what it found there.
    def failed(detail)
      @errors&.puts(detail)
      raise DatabaseError, "the database is unavailable"
    end

    # Nothing is wrong with the database or the statement: more is being
    # asked of it at once than it will take. The Host is the side that can
    # ask for less, so this is the operator's to read.
    def declined
      @errors&.puts("#{where} is taking no more statements at once")
      raise DatabaseBusy, "the database is busy"
    end

    def where = "#{@url}/#{@namespace}"

    def encode(param)
      case param
      when nil then { "type" => "null" }
      when Integer then { "type" => "integer", "value" => param.to_s }
      when Float then { "type" => "float", "value" => param }
      when String then { "type" => "text", "value" => param }
      else raise DatabaseError, "#{param.class} is no value a statement can carry"
      end
    end

    # Integers cross as strings, so the guest would read a count as text if
    # the type beside the value were not what decided.
    def decode(value)
      case value.fetch("type")
      when "null" then nil
      when "integer" then Integer(value.fetch("value"))
      when "float" then Float(value.fetch("value"))
      when "text" then value.fetch("value")
      # Padded or not depending on the length, which only the lenient
      # unpacking accepts.
      when "blob" then value.fetch("base64").unpack1("m")
      # A value the Host cannot name is one it would otherwise hand over as
      # nil, which reads as a column that held nothing.
      else failed("#{where} answered a #{value["type"]}, which this Host cannot read")
      end
    end
  end
end
