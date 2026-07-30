# frozen_string_literal: true

require "test_helper"

# What a Tenant's failure looks like from outside: a status that says whether
# retrying could help, a name for what went wrong, and nothing about the Host.
class FailureTest < TestHelper::Case
  # Small enough that exhausting them is quick; the Host applies one set to
  # every Tenant either way.
  TIGHT = Workers::Runtime.default(guest_binary: Workers.default_guest_binary)
                          .with(timeout: 0.5, memory_limit: 1024 * 1024)

  def test_a_manifest_that_is_not_json_leaves_the_tenant_unroutable
    get "/badjson"

    assert_equal 404, last_response.status
  end

  def test_source_that_does_not_compile_is_a_compile_failure
    get "/uncompilable"

    assert_failure 500, "compile_failure"
  end

  def test_a_manifest_naming_an_undefined_constant_is_an_undefined_entrypoint
    get "/noentry"

    assert_failure 500, "undefined_entrypoint"
  end

  def test_an_exception_the_worker_does_not_rescue_is_a_tenant_exception
    get "/broken"

    assert_failure 500, "tenant_exception"
  end

  def test_a_return_value_that_is_no_triplet_is_an_invalid_response
    get "/badtriplet"

    assert_failure 500, "invalid_response"
  end

  def test_a_refused_binding_call_left_unrescued_is_a_binding_failure
    get "/bindingfail"

    assert_failure 500, "binding_failure"
  end

  def test_exhausting_the_time_limit_is_a_timeout
    Workers::Host.set :runtime, TIGHT
    get "/hog"

    assert_failure 503, "timeout"
  end

  def test_exhausting_the_memory_limit_is_a_memory_limit
    Workers::Host.set :runtime, TIGHT
    get "/glutton"

    assert_failure 503, "memory_limit"
  end

  def test_a_trapped_sandbox_is_replaced_rather_than_dispatched_into_again
    Workers::Host.set :runtime, TIGHT

    # A Sandbox kept after a trap is unusable, and the next dispatch into it
    # reports corruption. Trapping the same way twice is what a rebuilt one
    # does.
    2.times { get "/hog" }

    assert_failure 503, "timeout"
  end

  def test_a_trap_leaves_the_other_tenants_answering
    Workers::Host.set :runtime, TIGHT
    get "/hog"

    assert_equal 503, last_response.status

    get "/hello"

    assert_equal 200, last_response.status
  end

  # A shared directory the Host cannot read is not a directory where nothing
  # was published. Answering 404 would say the endpoint is gone, when what is
  # gone is the Host's reach.
  def test_an_unreadable_shared_directory_answers_503_rather_than_404
    skip_as_superuser

    serving("served") do |root|
      File.chmod(0o000, root)

      get "/served"

      assert_equal 503, last_response.status
    end
  end

  def test_an_unreadable_shared_directory_is_recorded_for_the_operator
    skip_as_superuser

    serving("served") do |root|
      File.chmod(0o000, root)

      get "/served"

      assert_includes last_request.env["rack.errors"].string, root
      refute_includes last_response.body, root
    end
  end

  def test_a_cached_sandbox_does_not_serve_while_the_shared_directory_is_unreadable
    skip_as_superuser

    serving("served") do |root|
      get "/served"
      assert_equal 200, last_response.status

      File.chmod(0o000, root)
      get "/served"

      assert_equal 503, last_response.status
    end
  end

  def test_no_failure_names_a_path_the_host_keeps_its_files_under
    %w[badjson uncompilable noentry broken badtriplet bindingfail].each do |tenant|
      get "/#{tenant}"

      refute_includes last_response.body, Dir.pwd, "#{tenant} disclosed the working directory"
      refute_includes last_response.body, "/lib/workers", "#{tenant} disclosed a Host source path"
      refute_includes last_response.body, TestHelper::FIXTURE_APP_DIR, "#{tenant} disclosed the app directory"
    end
  end

  private

  # The superuser reads through any mode bits, so the boundary an unreadable
  # directory draws does not exist for that user.
  def skip_as_superuser
    skip "the superuser reads an unreadable directory" if Process.uid.zero?
  end

  def assert_failure(status, name)
    assert_equal status, last_response.status
    assert_equal name, last_response.body.strip
  end
end
