# frozen_string_literal: true

require "test_helper"
require "json"

# The mruby helpers every Sandbox carries: what a Worker may lean on without
# the Host having handed it anything, and what happens when a Tenant would
# rather define the name itself.
class RuntimeKitTest < TestHelper::Case
  def test_the_kit_shapes_a_plain_text_response
    get "/kit/text"

    assert_equal 200, last_response.status
    assert_equal "text/plain; charset=utf-8", last_response.headers["content-type"]
    assert_equal "plain", last_response.body
  end

  def test_the_kit_shapes_a_json_response
    get "/kit/json"

    assert_equal "application/json", last_response.headers["content-type"]
    assert_equal({ "shaped" => true }, JSON.parse(last_response.body))
  end

  def test_the_kit_shapes_a_response_carrying_a_chosen_status
    get "/kit/status"

    assert_equal 404, last_response.status
    assert_equal "gone", last_response.body
  end

  def test_a_worker_may_choose_the_status_and_add_headers_of_its_own
    get "/kit/custom"

    assert_equal 201, last_response.status
    assert_equal "yes", last_response.headers["x-kit"]
    assert_equal "text/plain; charset=utf-8", last_response.headers["content-type"]
  end

  def test_the_kit_reads_every_field_the_request_environment_carries
    post "/kit/items?q=1", "payload",
         { "CONTENT_TYPE" => "text/plain", "HTTP_X_PROBE" => "seen" }
    body = JSON.parse(last_response.body)

    assert_equal "POST", body["request_method"]
    assert_equal "/kit", body["script_name"]
    assert_equal "/items", body["path"]
    assert_equal({ "q" => "1" }, body["query"])
    assert_equal "seen", body["probe"]
    assert_equal "payload", body["body"]
  end

  def test_a_tenant_defining_a_kit_name_reaches_its_own_definition
    get "/shadow"

    assert_equal "the tenant's own", last_response.body
  end
end
