# frozen_string_literal: true

require "test_helper"
require "json"

# What a Tenant reaches through a Binding it declared, and what it does not
# reach through one it did not.
class DatabaseTest < TestHelper::Case
  MAIN = '{ "bindings": { "db": { "DB::Main": "main" } } }'

  # Nothing listens here, so a Host pointed at it reaches for a database and
  # finds no server at all.
  UNREACHABLE = "127.0.0.1:1"

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

  # An operator looking for a Tenant's database has only the Manifest to go
  # on, so what the two names resolve to is a contract rather than a detail.
  def test_a_database_takes_its_name_from_the_tenant_and_the_identifier
    storing
    serving("keeper", manifest: MAIN, source: probing('DB::Main.execute("create table t (n integer)")')) do
      get "/keeper"

      assert_equal 200, last_response.status
      assert_equal [ { "n" => 0 } ], reaching("keeper-main", "select count(*) as n from t")
    end
  end

  def test_a_constant_the_manifest_did_not_declare_does_not_exist
    answering("DB::Absent.query(\"select 1\")", manifest: MAIN) do
      assert_equal "NameError", body["error"]
    end
  end

  def test_a_tenant_reaches_no_database_another_tenant_declared
    storing
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

  # Each invocation reaches the one database on its own, and the server is
  # what puts the writes in an order, so none of them answers a failure for
  # having arrived while another was being served.
  def test_concurrent_invocations_writing_one_database_all_complete
    storing
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

  def test_a_database_the_host_cannot_reach_is_a_binding_failure
    stranding

    serving("stranded", manifest: MAIN, source: <<~RUBY) do
      App = ->(env) { DB::Main.query("select 1") }
    RUBY
      get "/stranded"

      assert_equal 500, last_response.status
      assert_equal "binding_failure", last_response.body.strip
    end
  end

  # Reaching the database at all is the Host's side of the contract. The
  # caller learns nothing it could act on, so the operator has to.
  def test_a_database_the_host_cannot_reach_is_recorded_for_the_operator
    stranding

    serving("stranded", manifest: MAIN, source: <<~RUBY) do
      App = ->(env) { DB::Main.query("select 1") }
    RUBY
      get "/stranded"

      assert_includes recorded, "stranded-main"
      assert_includes recorded, UNREACHABLE
      refute_includes last_response.body, UNREACHABLE
    end
  end

  # A Tenant that rescues an unreachable database learns that it is
  # unavailable, and not one thing about where the Host went looking.
  def test_a_database_the_host_cannot_reach_tells_the_tenant_nothing_of_where
    stranding

    serving("subject", manifest: MAIN, source: probing('DB::Main.query("select 1")')) do
      refute_nil body["error"]
      refute_includes body["message"], UNREACHABLE
    end
  end

  # The other side of that line: a statement the Tenant wrote is the Tenant's
  # to fix, and an operator paged for it would be paged for nothing.
  def test_a_statement_the_tenant_got_wrong_is_not_the_operators_to_see
    answering('DB::Main.query("select * from nowhere")', manifest: MAIN) do
      refute_nil body["error"]

      assert_empty recorded
    end
  end

  private

  def stranding
    Workers::Host.set :databases,
                      Workers::Databases.new(url: "http://#{UNREACHABLE}", admin_url: "http://#{UNREACHABLE}")
  end

  # The database as something other than the Host finds it, so which one the
  # Host wrote to is read rather than assumed.
  def reaching(namespace, sql)
    Workers::Hrana.new(url: Sqld.url, admin_url: Sqld.admin_url, namespace: namespace).query(sql, [])
  end

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
    storing
    serving("subject", manifest: manifest, source: probing(statements)) do
      yield
    end
  end

  def body
    get "/subject"

    JSON.parse(last_response.body)
  end

  def recorded = last_request.env["rack.errors"].string
end
