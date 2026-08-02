# frozen_string_literal: true

require "test_helper"

# What the Host says about itself when something outside it decides whether to
# replace it or to keep sending it requests.
class HealthTest < TestHelper::Case
  def test_liveness_answers_that_the_host_is_running
    get "/_health/live"

    assert_equal 200, last_response.status
    assert_empty last_response.body
  end

  def test_readiness_answers_while_the_shared_directory_is_readable
    get "/_health/ready"

    assert_equal 200, last_response.status
    assert_empty last_response.body
  end

  # E-11: every Tenant endpoint answers 503, and nothing outside the process
  # could tell that from a Host that is serving. This is what tells it.
  def test_readiness_stands_the_host_down_while_the_shared_directory_is_unreadable
    skip_as_superuser

    serving("served") do |root|
      File.chmod(0o000, root)

      get "/served"
      assert_equal 503, last_response.status

      get "/_health/ready"

      assert_equal 503, last_response.status
    end
  end

  # A replaced Host comes back to the same directory, so the check that ends
  # in a restart is not the one that reads it.
  def test_liveness_holds_while_the_shared_directory_is_unreadable
    skip_as_superuser

    serving("served") do |root|
      File.chmod(0o000, root)

      get "/_health/live"

      assert_equal 200, last_response.status
    end
  end

  # Every Host reaches the same database, so standing them all down over one
  # they cannot reach would leave the Tenants that declared no Binding with
  # nowhere to be served. The Tenant that did declare one is answered by its
  # own request failing, which is where that outage belongs.
  def test_a_database_no_host_can_reach_stands_none_of_them_down
    # Nothing listens here, so the Host reaches for the database and finds no
    # server at all.
    Workers::Host.set :databases,
                      Workers::Databases.new(url: "http://127.0.0.1:1", admin_url: "http://127.0.0.1:1")

    serving("stranded", manifest: '{ "bindings": { "db": { "DB::Main": "main" } } }', source: <<~RUBY) do
      App = ->(env) { DB::Main.query("select 1") }
    RUBY
      get "/stranded"
      assert_equal 500, last_response.status

      get "/_health/ready"

      assert_equal 200, last_response.status
    end
  end

  # A Tenant reaching the Host under a domain it declared answers every path
  # that domain carries — except these, which were never its to answer.
  def test_a_tenant_serving_its_own_domain_does_not_answer_these
    serving("claimant", manifest: '{ "domain": "example.com" }', body: "the tenant") do
      get "/anything", {}, { "HTTP_HOST" => "example.com" }
      assert_equal "the tenant", last_response.body

      get "/_health/ready", {}, { "HTTP_HOST" => "example.com" }

      assert_equal 200, last_response.status
      assert_empty last_response.body
    end
  end

  # The question is asked with a GET; a request arriving any other way is read
  # as naming a Tenant, and no Tenant may be named this.
  def test_another_method_reaches_no_tenant_either
    post "/_health/live"

    assert_equal 404, last_response.status
  end
end
