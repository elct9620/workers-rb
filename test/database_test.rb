# frozen_string_literal: true

require "test_helper"
require "json"

# What a Tenant reaches through a Binding it declared, and what it does not
# reach through one it did not.
class DatabaseTest < TestHelper::Case
  MAIN = '{ "bindings": { "db": { "DB::Main": "main" } } }'

  def test_a_declared_binding_answers_a_query_with_rows_of_columns
    answering(<<~RUBY) do
      DB::Main.execute("create table if not exists notes (id integer, note text)")
      DB::Main.execute("insert into notes values (?, ?)", 1, "first")
      DB::Main.query("select id, note from notes")
    RUBY
      assert_equal [ { "id" => 1, "note" => "first" } ], body["value"]
    end
  end

  def test_a_write_answers_with_the_rows_it_affected
    answering(<<~RUBY) do
      DB::Main.execute("create table if not exists notes (id integer)")
      DB::Main.execute("insert into notes values (1), (2), (3)")
    RUBY
      assert_equal 3, body["value"]
    end
  end

  def test_a_write_is_there_for_the_request_that_comes_after_it
    answering(<<~RUBY) do
      DB::Main.execute("create table if not exists tally (n integer)")
      DB::Main.execute("insert into tally values (1)")
      DB::Main.query("select count(*) as seen from tally")
    RUBY
      assert_equal [ { "seen" => 1 } ], body["value"]
      assert_equal [ { "seen" => 2 } ], body["value"]
    end
  end

  def test_a_database_file_takes_its_name_from_the_tenant_and_the_identifier
    mounting do |mount|
      serving("keeper", manifest: MAIN, source: probing('DB::Main.execute("create table t (n integer)")')) do
        get "/keeper"

        assert_equal [ "keeper-main.db" ], Dir.children(mount)
      end
    end
  end

  def test_a_constant_the_manifest_did_not_declare_does_not_exist
    answering("DB::Absent.query(\"select 1\")", manifest: MAIN) do
      assert_equal "NameError", body["error"]
    end
  end

  def test_a_tenant_reaches_no_database_another_tenant_declared
    mounting do
      serving("owner", manifest: MAIN, source: probing(<<~RUBY)) do |root|
        DB::Main.execute("create table if not exists secrets (word text)")
        DB::Main.execute("insert into secrets values ('open sesame')")
      RUBY
        get "/owner"
        assert_equal 200, last_response.status

        # The neighbour declares a Binding of its own under the same constant,
        # so the name resolves — to its own database, holding no such table.
        publish(root, "neighbour", manifest: MAIN, source: probing('DB::Main.query("select * from secrets")'))
        get "/neighbour"

        assert_includes JSON.parse(last_response.body)["message"], "no such table: secrets"
      end
    end
  end

  def test_a_statement_the_database_refuses_is_the_tenants_to_rescue
    answering('DB::Main.query("select * from nowhere")', manifest: MAIN) do
      refute_nil body["error"], "the statement did not fail"
      assert_includes body["message"], "no such table: nowhere"
    end
  end

  def test_two_declared_bindings_are_two_databases
    manifest = '{ "bindings": { "db": { "DB::Main": "main", "DB::Logs": "logs" } } }'

    answering(<<~RUBY, manifest: manifest) do
      DB::Main.execute("create table if not exists here (n integer)")
      DB::Logs.execute("create table if not exists here (n integer)")
      DB::Main.execute("insert into here values (1)")
      DB::Logs.query("select count(*) as seen from here")
    RUBY
      assert_equal [ { "seen" => 0 } ], body["value"]
    end
  end

  # Each invocation holds its own connection to the one file, so a writer that
  # meets another's lock waits for it rather than answering a failure.
  def test_concurrent_invocations_writing_one_database_all_complete
    mounting do
      serving("busy", manifest: MAIN, source: probing(<<~RUBY)) do
        DB::Main.execute("create table if not exists hits (n integer)")
        DB::Main.execute("insert into hits values (1)")
        DB::Main.query("select count(*) as n from hits")[0]["n"]
      RUBY
        get "/busy" # settle the table before the burst

        answers = 12.times.map {
          Thread.new { Rack::MockRequest.new(Workers::Host).get("/busy") }
        }.map { |thread| JSON.parse(thread.value.body) }

        assert_empty(answers.filter_map { |answer| answer["message"] })
        assert_equal 13, answers.filter_map { |answer| answer["value"] }.max
      end
    end
  end

  def test_a_mount_the_host_cannot_open_is_a_binding_failure
    Workers::Host.set :databases, Workers::Databases.new(root: "/no/such/mount")

    serving("stranded", manifest: MAIN, source: <<~RUBY) do
      App = ->(env) { DB::Main.query("select 1") }
    RUBY
      get "/stranded"

      assert_equal 500, last_response.status
      assert_equal "binding_failure", last_response.body.strip
    end
  end

  private

  # A Worker that answers with whatever the statements evaluated to, or with
  # the class of whatever they raised.
  def probing(statements)
    <<~RUBY
      App = ->(env) {
        begin
          value = begin
            #{statements.strip.lines.join("          ")}
          end
          body = JSON.generate({ "value" => value })
        rescue => e
          body = JSON.generate({ "error" => e.class.to_s, "message" => e.message.to_s })
        end
        [200, { "content-type" => "application/json" }, [body]]
      }
    RUBY
  end

  def answering(statements, manifest: MAIN)
    mounting do
      serving("subject", manifest: manifest, source: probing(statements)) do
        yield
      end
    end
  end

  def body
    get "/subject"

    JSON.parse(last_response.body)
  end
end
