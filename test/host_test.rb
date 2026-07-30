# frozen_string_literal: true

require "test_helper"
require "json"

class HostTest < TestHelper::Case
  def test_path_form_routes_to_the_tenant_named_by_the_first_segment
    get "/hello"

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response.headers["content-type"]
    assert_equal "hello from \n", last_response.body
  end

  def test_the_tenant_segment_leaves_the_worker_the_remaining_path
    get "/hello/items"

    assert_equal "hello from /items\n", last_response.body
  end

  def test_an_unknown_first_segment_is_not_routable
    get "/nobody"

    assert_equal 404, last_response.status
  end

  def test_the_manifest_names_the_entrypoint_the_host_dispatches
    get "/refused"

    assert_equal 200, last_response.status
  end

  def test_tenant_files_load_in_lexicographic_order
    get "/refused"

    # `main.rb` calls `Attempt`, which `00_attempt.rb` defines.
    refute_equal "NameError", JSON.parse(last_response.body)["allowed"]
  end

  def test_the_clock_and_entropy_reach_tenant_code_as_bindings
    get "/ambient/dice"
    body = JSON.parse(last_response.body)

    assert_in_delta ::Time.now.to_f, body["time"], 5.0
    assert_includes 0..5, body["roll"]
    assert_includes 0.0..1.0, body["unit"]
  end

  def test_the_guest_carries_json_and_ascii_regexp
    get "/ambient/dice"

    assert_equal "application/json", last_response.headers["content-type"]
    assert JSON.parse(last_response.body)["matched"]
  end

  def test_a_method_outside_the_allow_list_is_refused_rather_than_answered
    get "/refused"
    body = JSON.parse(last_response.body)

    assert_equal "Float", body["allowed"]
    assert_equal "Kobako::ServiceError", body["refused_clock"]
    assert_equal "Kobako::ServiceError", body["refused_entropy"]
    assert_equal "Kobako::ServiceError", body["refused_env"]
  end

  def test_the_request_environment_carries_every_field_it_declares
    post "/surface/items?q=1", "payload",
         { "CONTENT_TYPE" => "text/plain", "HTTP_X_PROBE" => "seen" }
    body = JSON.parse(last_response.body)

    assert_equal "POST", body["request_method"]
    assert_equal "/surface", body["script_name"]
    assert_equal "/items", body["path"]
    assert_equal({ "q" => "1" }, body["query"])
    assert_equal "seen", body["probe"]
    assert_equal "payload", body["body"]
  end

  # What the Host leaves out has no name in the guest at all, so the keys are
  # part of the contract rather than a starting point.
  def test_the_request_environment_carries_nothing_beyond_those_fields
    get "/surface"

    assert_equal %w[body headers path query request_method script_name],
                 JSON.parse(last_response.body)["keys"]
  end

  # `query` is the query string's, so a form field a Worker wants is one it
  # reads out of the body itself.
  def test_a_form_field_is_no_query_parameter
    post "/surface", "shipped=yes", { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    body = JSON.parse(last_response.body)

    assert_empty body["query"]
    assert_equal "shipped=yes", body["body"]
  end

  def test_a_failing_tenant_answers_without_disclosing_the_host
    get "/broken"

    assert_equal 500, last_response.status
    refute_includes last_response.body, Dir.pwd
    refute_includes last_response.body, "tenant.rb"
  end

  def test_a_failing_tenant_leaves_its_neighbours_answering
    get "/broken"
    get "/hello"

    assert_equal 200, last_response.status
  end

  def test_editing_a_tenant_serves_the_change_on_the_next_request
    serving("mutable", body: "first") do |root|
      get "/mutable"
      assert_equal "first", last_response.body

      publish(root, "mutable", body: "second")
      get "/mutable"

      assert_equal "second", last_response.body
    end
  end

  def test_concurrent_requests_to_one_tenant_each_carry_their_own_bindings
    paths = 8.times.map { |n|
      Thread.new { Rack::MockRequest.new(Workers::Host).get("/surface/req#{n}") }
    }.map { |thread| JSON.parse(thread.value.body)["path"] }

    assert_equal (0...8).map { |n| "/req#{n}" }, paths
  end

  def test_a_removed_tenant_stops_being_routable_and_lets_its_sandbox_go
    serving("ephemeral") do |root|
      get "/ephemeral"
      assert_equal 200, last_response.status

      FileUtils.rm_rf(File.join(root, "ephemeral"))
      get "/ephemeral"
      assert_equal 404, last_response.status

      # A released Sandbox has no outward sign, so the assertion reads the
      # registry that would otherwise keep it alive.
      assert_empty(registry.select { |(dir, _), _| dir.start_with?(root) })
    end
  end

  # A Tenant nobody asks for again is never reached, so nothing would evict it
  # on its own. The bound is what keeps a long-lived Host from holding every
  # Sandbox it ever built.
  def test_the_host_holds_no_more_sandboxes_than_its_bound_allows
    cap = Workers::Tenant::CACHED
    runtime = Workers::Runtime.default

    serving("eldest") do |root|
      Workers::Tenant.find(root, "eldest", runtime: runtime)

      cap.times do |n|
        publish(root, "filler#{n}")
        Workers::Tenant.find(root, "filler#{n}", runtime: runtime)
      end

      assert_operator registry.size, :<=, cap
      refute_includes registry.keys.map(&:first), File.join(root, "eldest")
    end
  end

  private

  def registry = Workers::Tenant.const_get(:REGISTRY, false)
end
