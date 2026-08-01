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

  # A Manifest is what publishes a Tenant, so source sitting beside no
  # Manifest is source nobody published.
  def test_a_directory_holding_no_manifest_is_no_tenant
    serving("published") do |root|
      dir = File.join(root, "unpublished")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "main.rb"), worker("here"))

      get "/unpublished"

      assert_equal 404, last_response.status
    end
  end

  # A Tenant name reaches the cluster as a hostname label and names a database
  # beside it, so a directory named outside the rule is one the Host declines
  # to read as a Tenant at all.
  def test_a_directory_named_outside_the_rule_is_no_tenant
    serving("published") do |root|
      %w[Hello -lead trail- under_score].each do |name|
        publish(root, name)

        get "/#{name}"

        assert_equal 404, last_response.status, "#{name.inspect} routed"
      end
    end
  end

  def test_a_name_at_the_length_limit_is_a_tenant_and_one_past_it_is_not
    longest = "a" * 63

    serving(longest) do |root|
      get "/#{longest}"

      assert_equal 200, last_response.status

      publish(root, "#{longest}a")
      get "/#{longest}a"

      assert_equal 404, last_response.status
    end
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

  # A Binding is refused by the Host; the environment, the filesystem and the
  # network are not refused by anyone — the guest binary carries no name for
  # them, so tenant code cannot spell a way out. Nothing in the Host enforces
  # that, which is why it is asserted here: a build that carried `File` would
  # pass every other test in this suite.
  def test_the_sandbox_reaches_no_environment_no_filesystem_and_no_network
    get "/closed"
    reached = JSON.parse(last_response.body)

    %w[environment filesystem directory network].each do |way_out|
      assert_match(/\ANameError/, reached[way_out], "#{way_out} named something the guest could reach")
    end
    assert_match(/\ANoMethodError/, reached["shell"], "the guest reached a shell")
    refute_includes last_response.body, Dir.pwd, "a refusal named where the Host runs"
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

  # A Worker's `puts` is its only way to say anything that is not a response.
  # It reaches the operator, who is the one who can act on it, and it reaches
  # the caller under no circumstance.
  def test_what_a_worker_writes_reaches_the_operator_and_not_the_caller
    get "/talkative/here"

    assert_includes recorded, "talkative out: worked on /here"
    assert_includes recorded, "talkative err: and had something to say about it"
    refute_includes last_response.body, "worked on"
  end

  # The invocation that failed is the one whose output is worth most, and it
  # is the one that never returns a value to read it off.
  def test_a_worker_that_failed_still_says_what_it_wrote
    get "/talkative/fail"

    assert_equal 500, last_response.status
    assert_includes recorded, "talkative out: worked on /fail"
  end

  # B-13: what one invocation wrote ends with it. A capture that carried into
  # the next would have the operator reading a Worker's earlier words as this
  # request's, and reading them again on every request after that.
  def test_what_one_invocation_wrote_does_not_reach_the_next
    get "/talkative/first"
    get "/talkative/second"

    assert_includes recorded, "talkative out: worked on /second"
    refute_includes recorded, "worked on /first"
  end

  # An operator reading a Worker's last words needs to know they are its last
  # words rather than all of them. The request itself is unaffected: what the
  # limit bounds is what the Host keeps, not what the Worker may do.
  def test_output_past_the_limit_is_marked_as_clipped
    Workers::Host.set :runtime, Workers::Runtime.default.with(output_limit: 8)
    get "/talkative/here"

    assert_equal 200, last_response.status
    assert_includes recorded, "talkative out: clipped at the limit"
    assert_includes recorded, "talkative err: clipped at the limit"
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

  # The Manifest decides what the Sandbox is built with, so rewriting it alone
  # has to reach the next request as surely as rewriting the source does.
  def test_editing_only_the_manifest_serves_the_change_on_the_next_request
    source = <<~RUBY
      App = ->(env) { [200, { "content-type" => "text/plain" }, ["first"]] }
      Other = ->(env) { [200, { "content-type" => "text/plain" }, ["second"]] }
    RUBY

    serving("switched", source: source) do |root|
      get "/switched"
      assert_equal "first", last_response.body

      File.write(File.join(root, "switched", "app.json"), '{ "entrypoint": "Other" }')
      get "/switched"

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
    cap = Workers::Registry::CACHED
    runtime = Workers::Runtime.default

    serving("eldest") do |root|
      Workers::Registry.find(root, "eldest", runtime: runtime)

      cap.times do |n|
        publish(root, "filler#{n}")
        Workers::Registry.find(root, "filler#{n}", runtime: runtime)
      end

      assert_operator registry.size, :<=, cap
      refute_includes registry.keys.map(&:first), File.join(root, "eldest")
    end
  end

  private

  def recorded = last_request.env["rack.errors"].string

  def registry = Workers::Registry.const_get(:TENANTS, false)
end
