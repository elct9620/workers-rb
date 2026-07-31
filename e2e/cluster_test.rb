# frozen_string_literal: true

require "bundler/setup"
require "json"
require "minitest/autorun"
require "net/http"
require "uri"

# The cluster as a caller reaches it: several Hosts behind one address, none of
# them named by the request. Nothing here loads the Host or selects a Node, so
# what is asserted is what a tenant author or an operator could see for
# themselves — which is the only way the properties SPEC.md F-08 states can be
# checked at all.
class ClusterTest < Minitest::Test
  ADDRESS = URI(ENV.fetch("WORKERS_E2E_URL", "http://localhost:9292"))
  BASE_DOMAIN = ENV.fetch("WORKERS_E2E_BASE_DOMAIN", "workers.test")
  NODES = Integer(ENV.fetch("WORKERS_E2E_NODES", "3"))

  # Three turns of the rotation, so every Node answers whichever one the first
  # request happened to land on.
  ROUNDS = NODES * 3

  def setup = self.class.answering!

  # The cluster is started outside the suite, and a Node that has just come up
  # is not yet listening. Waited for once rather than per test.
  def self.answering!
    return if @answering

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    begin
      Net::HTTP.get_response(ADDRESS)
    rescue SystemCallError, IOError
      raise "no Host answered at #{ADDRESS} — `docker compose up -d --wait` first" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.5
      retry
    end

    @answering = true
  end

  # A Tenant is published to the cluster rather than to a Node, so whichever
  # Node answers has to know it. Nothing here picks the Node — the spread over
  # the rounds is what brings every Node into the answer.
  def test_a_tenant_published_once_answers_from_every_node
    answers = Array.new(ROUNDS) { get("/where") }

    assert_equal NODES, answers.map { |body| body.fetch("node") }.uniq.size
    assert_equal [ "where" ], answers.map { |body| body.fetch("tenant") }.uniq
  end

  def test_the_path_form_spends_a_segment_naming_the_tenant
    body = get("/where/items")

    assert_equal [ "where", "/where", "/items" ], body.values_at("tenant", "script_name", "path")
  end

  def test_a_tenant_answers_under_the_base_domain
    body = get("/items", host: "where.#{BASE_DOMAIN}")

    assert_equal [ "where", "", "/items" ], body.values_at("tenant", "script_name", "path")
  end

  def test_a_tenant_answers_under_the_domain_its_manifest_declares
    body = get("/items", host: "shop.example")

    assert_equal [ "shop", "", "/items" ], body.values_at("tenant", "script_name", "path")
  end

  def test_a_hostname_and_a_path_naming_no_tenant_are_answered_as_404
    assert_equal "404", response("/nothing-published-here").code
    assert_equal "404", response("/", host: "nobody.example").code
  end

  # Each write lands on whichever Node the proxy chose and the read that
  # follows lands on another, and what the caller counts is one ledger.
  def test_a_write_from_any_node_is_there_for_a_read_from_the_next
    before = get("/ledger").fetch("entries")
    nodes = Array.new(ROUNDS) { post("/ledger").fetch("node") }

    assert_equal NODES, nodes.uniq.size
    assert_equal before + ROUNDS, get("/ledger").fetch("entries")
  end

  private

  def get(path, host: nil) = JSON.parse(response(path, host: host).body)
  def post(path, host: nil) = JSON.parse(response(path, host: host, verb: Net::HTTP::Post).body)

  def response(path, host: nil, verb: Net::HTTP::Get)
    request = verb.new(path)
    # Net::HTTP fills the Host header in from the address it dialled, so the
    # domain forms need it said explicitly — exactly as the tunnel would.
    request["Host"] = host if host

    if request.request_body_permitted?
      # The write carries no payload, and saying so keeps Net::HTTP from
      # guessing a form encoding on the caller's behalf.
      request["content-type"] = "application/json"
      request.body = "{}"
    end

    Net::HTTP.start(ADDRESS.host, ADDRESS.port) { |http| http.request(request) }
  end
end
