# frozen_string_literal: true

require "test_helper"

# What a Tenant's failure looks like from outside: a status that says whether
# retrying could help, a name for what went wrong, and nothing about the Host.
class FailureTest < TestHelper::Case
  # Small enough that exhausting them is quick; the Host applies one set to
  # every Tenant either way.
  TIGHT = Workers::Runtime.default.with(timeout: 0.5, memory_limit: 1024 * 1024)

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

  # A Tenant that misnamed its entrypoint has the response and nothing else to
  # correct it from. The names listed are its own and the Runtime Kit's, so
  # answering with them says nothing about the Host.
  def test_an_undefined_entrypoint_lists_what_the_sandbox_does_define
    get "/noentry"

    defined = last_response.body.lines.last

    assert_match(/\Adefined: /, defined)
    assert_includes defined, "App", "the Tenant defines this and the Manifest asked for another"
    assert_includes defined, "Request", "the Runtime Kit's constants are the Sandbox's too"
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

  # The one failure class no Tenant can ask for: the Sandbox answers with
  # something the wire cannot frame, so what comes back is unusable rather
  # than wrong. Reached here by handing the guest a String larger than its
  # mruby build holds — the bound `BodyLimit` keeps every caller on the other
  # side of, which is why no request can arrive at this.
  def test_a_sandbox_that_answered_nothing_readable_is_runtime_corruption
    sandbox = Workers::Runtime.default.sandbox
    sandbox.preload(code: "App = ->(env) { env }", name: "Probe")

    error = assert_raises(Kobako::TrapError) { sandbox.run(:App, "a" * (1024 * 1024)) }
    failure = Workers::Failure.for(error)

    assert_equal "runtime_corruption", failure.name
    assert_equal 503, failure.status
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

  # The failure class is the whole of the first line, whatever a failure goes
  # on to say for itself after it.
  def assert_failure(status, name)
    assert_equal status, last_response.status
    assert_equal name, last_response.body.lines.first.strip
  end
end
