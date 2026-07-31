# frozen_string_literal: true

require "test_helper"

# How a request finds its Tenant. Three forms reach the same Tenant, and they
# are tried in one order: the domain a Manifest declared, then `<tenant>` under
# the Host's base domain, then the path's first segment. Only the last spends a
# segment naming the Tenant; under either domain form the Worker receives the
# whole path.
class RoutingTest < TestHelper::Case
  # A Worker that says which Tenant answered and where the Host mounted it.
  LANDING = <<~RUBY
    App = ->(env) {
      body = JSON.generate(
        "tenant" => Env.tenant,
        "script_name" => env["script_name"],
        "path" => env["path"]
      )
      [200, { "content-type" => "application/json" }, [body]]
    }
  RUBY

  def test_the_paths_first_segment_names_the_tenant
    serving("plain", source: LANDING) do
      get "/plain/items"

      assert_equal({ "tenant" => "plain", "script_name" => "/plain", "path" => "/items" }, landing)
    end
  end

  def test_a_declared_domain_leaves_the_whole_path_to_the_worker
    serving("shop", manifest: '{ "domain": "example.com" }', source: LANDING) do
      get "http://example.com/items"

      assert_equal({ "tenant" => "shop", "script_name" => "", "path" => "/items" }, landing)
    end
  end

  def test_a_tenant_under_the_base_domain_leaves_the_whole_path_to_the_worker
    Workers::Host.set :base_domain, "workers.test"

    serving("shop", source: LANDING) do
      get "http://shop.workers.test/items"

      assert_equal({ "tenant" => "shop", "script_name" => "", "path" => "/items" }, landing)
    end
  end

  def test_the_base_domain_form_waits_for_the_operator_to_configure_one
    serving("shop", source: LANDING) do
      get "http://shop.workers.test/items"

      assert_equal 404, last_response.status
    end
  end

  def test_a_declared_domain_outranks_the_base_domain_form
    Workers::Host.set :base_domain, "workers.test"

    serving("shop", manifest: '{ "domain": "other.workers.test" }', source: LANDING) do |root|
      publish(root, "other", source: LANDING)
      get "http://other.workers.test/items"

      assert_equal "shop", landing["tenant"]
    end
  end

  def test_the_base_domain_form_outranks_the_path_form
    Workers::Host.set :base_domain, "workers.test"

    serving("shop", source: LANDING) do |root|
      publish(root, "other", source: LANDING)
      get "http://shop.workers.test/other/items"

      assert_equal({ "tenant" => "shop", "script_name" => "", "path" => "/other/items" }, landing)
    end
  end

  # The Host answers under whatever hostname reaches it, so a Host header that
  # names no Tenant is no reason to stop looking.
  def test_a_host_header_naming_no_tenant_leaves_the_path_form
    Workers::Host.set :base_domain, "workers.test"

    serving("plain", source: LANDING) do
      get "http://localhost/plain/items"

      assert_equal "plain", landing["tenant"]
    end
  end

  # The Tenant is what a domain selects, so the port the caller reached the
  # Host on says nothing about which one.
  def test_the_port_the_request_arrived_on_is_no_part_of_the_domain
    serving("shop", manifest: '{ "domain": "example.com" }', source: LANDING) do
      get "http://example.com:9292/items"

      assert_equal "shop", landing["tenant"]
    end
  end

  def test_a_domain_no_tenant_declared_reaches_no_tenant
    serving("shop", manifest: '{ "domain": "example.com" }', source: LANDING) do
      get "http://unclaimed.test/items"

      assert_equal 404, last_response.status
    end
  end

  # A domain follows the Manifest that declares it, and the Manifest is read
  # from the shared directory on every request.
  def test_a_domain_withdrawn_from_the_manifest_stops_routing
    serving("shop", manifest: '{ "domain": "example.com" }', source: LANDING) do |root|
      get "http://example.com/items"
      assert_equal 200, last_response.status

      publish(root, "shop", manifest: "{}", source: LANDING)
      get "http://example.com/items"

      assert_equal 404, last_response.status
    end
  end

  private

  def landing = JSON.parse(last_response.body)
end
