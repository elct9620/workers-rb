# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "tmpdir"

class HostTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Workers::Host.set :app_dir, @app_dir || TestHelper::FIXTURE_APP_DIR
    Workers::Host
  end

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
    assert_equal "Kobako::ServiceError", body["refused_request"]
  end

  def test_the_worker_reads_every_field_the_request_surface_declares
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
    Dir.mktmpdir do |root|
      @app_dir = root
      tenant = File.join(root, "mutable")
      FileUtils.mkdir_p(tenant)
      File.write(File.join(tenant, "app.json"), "{}")
      write_worker(tenant, "first")

      get "/mutable"
      assert_equal "first", last_response.body

      write_worker(tenant, "second")
      get "/mutable"
      assert_equal "second", last_response.body
    end
  end

  private

  def write_worker(dir, body)
    File.write(File.join(dir, "main.rb"), <<~RUBY)
      App = ->(request) { [200, { "content-type" => "text/plain" }, ["#{body}"]] }
    RUBY
  end
end
