# frozen_string_literal: true

require "test_helper"
require "json"
require "socket"

# What an invocation knows about where it is running: the Node that executed
# it, whether that Node may write, the Tenant it belongs to, and an identity
# for this request alone.
class EnvTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Workers::Host.set :app_dir, TestHelper::FIXTURE_APP_DIR
    Workers::Host.set :node, @node || Workers::Node.current
    Workers::Host
  end

  def test_the_node_a_host_runs_on_is_the_one_the_operating_system_reports
    assert_equal Socket.gethostname, Workers::Node.current.name
  end

  def test_a_node_is_the_writer_only_when_the_operator_designates_it
    refute_predicate Workers::Node.current({}), :writer?
    assert_predicate Workers::Node.current({ "WORKERS_WRITER" => "true" }), :writer?
  end

  def test_env_reports_the_node_that_executed_the_invocation
    @node = Workers::Node.new(name: "node-elsewhere", writer: false)

    assert_equal "node-elsewhere", body["node"]
  end

  def test_env_reports_whether_that_node_may_write
    @node = Workers::Node.new(name: "node-writer", writer: true)

    assert_equal true, body["writer"]
  end

  def test_env_names_the_tenant_the_worker_belongs_to
    assert_equal "env", body["tenant"]
  end

  def test_each_request_carries_an_identity_of_its_own
    first = body["request_id"]
    second = body["request_id"]

    refute_empty first
    refute_equal first, second
  end

  def test_one_invocation_reads_one_identity_however_often_it_asks
    assert_equal true, body["stable"]
  end

  private

  def body
    get "/env"

    JSON.parse(last_response.body)
  end
end
