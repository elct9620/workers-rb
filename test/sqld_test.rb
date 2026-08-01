# frozen_string_literal: true

require "test_helper"
require "sqld"

# What a run leaves behind once it is done with the database server, which
# has to be nothing whichever way the run ended.
#
# The server outlives every individual test by design, so the only place its
# shutdown can be observed is from outside a run: each test here starts one
# in a run of its own and then asks the port whether anything still answers.
class SqldTest < Minitest::Test
  def test_the_server_answers_where_the_host_would_reach_it
    address = URI(Sqld.url)

    assert_equal "404", probe(address, "/v2/pipeline").code,
                 "a namespace nobody created should not resolve"
  end

  def test_a_dropped_namespace_stops_resolving
    created = Net::HTTP::Post.new("/v1/namespaces/dropme/create", "content-type" => "application/json")
    created.body = "{}"
    Net::HTTP.start(URI(Sqld.admin_url).host, URI(Sqld.admin_url).port) { |http| http.request(created) }

    Sqld.drop("dropme")

    assert_equal "404", probe(URI(Sqld.url), "/v2/pipeline", host: "dropme.libsql").code
  end

  def test_the_server_is_gone_once_the_run_that_started_it_ends
    port = run_holding_a_server { |child| child.close_write }

    refute listening?(port), "the server outlived the run that started it"
  end

  def test_the_server_is_gone_once_the_run_is_asked_to_stop
    port = run_holding_a_server { |child| Process.kill("TERM", child.pid) }

    refute listening?(port), "the server outlived the run it was asked to stop"
  end

  private

  # Reports the port and then holds, so the run lasts long enough to be
  # observed holding it. Reaching the end of its input is what lets the run
  # finish on its own; a signal is the other way it can end. The flush is
  # because a pipe is block-buffered, and a run that goes on to wait would
  # otherwise report nothing until it stopped waiting.
  HOLDING = "puts URI(Sqld.url).port; $stdout.flush; $stdin.gets"
  private_constant :HOLDING

  # A run of its own holding a server: the port it took is reported back, and
  # the block decides how that run ends.
  def run_holding_a_server
    child = IO.popen([ RbConfig.ruby, "-I#{__dir__}", "-ruri", "-rsqld", "-e", HOLDING ], "r+")
    port = Integer(child.gets)
    # Otherwise a run that never started a server would answer every question
    # about what it left behind with the same silence as one that cleaned up.
    assert listening?(port), "the run reported a port nothing was listening on"

    yield child
    # Waits for the run to end, which is what its shutdown hangs off.
    child.close

    # The port it held is free only once the operating system has taken it
    # back, which trails the run it belonged to.
    30.times { break unless listening?(port); sleep 0.1 }
    port
  end

  def probe(address, path, host: "nobody.libsql")
    request = Net::HTTP::Post.new(path, "content-type" => "application/json")
    request["Host"] = host
    request.body = '{"requests":[{"type":"close"}]}'
    Net::HTTP.start(address.host, address.port) { |http| http.request(request) }
  end

  def listening?(port)
    TCPSocket.new("127.0.0.1", port).close
    true
  rescue SystemCallError
    false
  end
end
