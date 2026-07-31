# frozen_string_literal: true

require "test_helper"

# What the Host accepts as a Manifest. Every field is optional, so an empty
# object configures a Tenant completely; a field that says something the Host
# cannot act on makes the Tenant unroutable rather than half-configured.
class ManifestTest < TestHelper::Case
  VIOLATIONS = {
    "a Manifest that is not a JSON object" => '["not an object"]',
    "an entrypoint that is not a String" => '{ "entrypoint": 7 }',
    "a domain that is not a String" => '{ "domain": ["example.com"] }',
    "bindings that are not an object" => '{ "bindings": [] }',
    "a db declaration that is not an object" => '{ "bindings": { "db": "main" } }',
    "a Binding constant outside DB::" => '{ "bindings": { "db": { "Main": "main" } } }',
    "a Binding constant not starting uppercase" => '{ "bindings": { "db": { "DB::main": "main" } } }',
    "a database identifier carrying a dash" => '{ "bindings": { "db": { "DB::Main": "main-db" } } }',
    "a database identifier carrying uppercase" => '{ "bindings": { "db": { "DB::Main": "Main" } } }',
    "a database identifier that is not a String" => '{ "bindings": { "db": { "DB::Main": 1 } } }',
    "a database identifier past 32 characters" => %({ "bindings": { "db": { "DB::Main": "#{"a" * 33}" } } })
  }.freeze

  def test_a_manifest_the_host_cannot_act_on_leaves_the_tenant_unroutable
    VIOLATIONS.each do |violation, manifest|
      assert_equal 404, status_for(manifest), violation
    end
  end

  def test_an_empty_object_configures_a_tenant_completely
    assert_equal 200, status_for("{}")
  end

  def test_a_manifest_declaring_every_field_stays_routable
    assert_equal 200, status_for(<<~JSON)
      {
        "entrypoint": "App",
        "domain": "example.com",
        "bindings": { "db": { "DB::Main": "main", "DB::Logs": "logs_2" } }
      }
    JSON
  end

  # Deciding where a request goes means reading what every Tenant published,
  # so a Manifest the Host cannot act on has to cost its own Tenant the route
  # and no other. The unroutable one is named to sort first, where a reader
  # that gave up on the first one it could not act on would be caught.
  def test_a_manifest_the_host_cannot_act_on_costs_no_other_tenant_its_route
    serving("sound", body: "answered") do |root|
      publish(root, "ailing", manifest: '{ "entrypoint": 7 }')

      get "/sound"

      assert_equal "answered", last_response.body
    end
  end

  def test_an_unroutable_tenant_is_recorded_for_the_operator
    status_for('{ "domain": ["example.com"] }')

    assert_includes last_request.env["rack.errors"].string, "tenant"
    assert_includes last_request.env["rack.errors"].string, "domain"
  end

  private

  def status_for(manifest)
    serving("subject", manifest: manifest) do
      get "/subject"
      last_response.status
    end
  end
end
