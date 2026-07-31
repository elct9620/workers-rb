# frozen_string_literal: true

require "test_helper"
require "json"
require "socket"

# What an invocation knows about where it is running: the Node that executed
# it, the Tenant it belongs to, and an identity for this request alone.
class EnvTest < TestHelper::Case
  def test_the_node_a_host_runs_on_is_the_one_the_operating_system_reports
    assert_equal Socket.gethostname, Workers::Node.current.name
  end

  def test_env_reports_the_node_that_executed_the_invocation
    Workers::Host.set :node, Workers::Node.new(name: "node-elsewhere")

    assert_equal "node-elsewhere", body["node"]
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
