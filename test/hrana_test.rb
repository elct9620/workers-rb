# frozen_string_literal: true

require "test_helper"
require "unresponsive"
require "sqld"

# What the Host gets back from a database it reaches over the network, driven
# against the server the cluster runs rather than a description of it.
class HranaTest < Minitest::Test
  # A database of this test's own, and empty however often the suite has run
  # before: what one test wrote would otherwise be the next one's first row.
  def setup
    @namespace = "hrana-#{name}"
    Sqld.drop(@namespace)
  end

  def test_a_query_answers_with_rows_of_columns
    database.execute("create table notes (id integer, note text)", [])
    database.execute("insert into notes values (?, ?)", [ 1, "first" ])

    assert_equal [ { "id" => 1, "note" => "first" } ], database.query("select id, note from notes", [])
  end

  # The wire carries an integer as text, so a count read straight off it would
  # reach tenant code as the String "3".
  def test_a_row_carries_the_types_the_guest_is_promised
    row = database.query("select 1 as i, 1.5 as f, 'text' as t, null as n, x'0102' as b", []).first

    assert_equal 1, row["i"]
    assert_in_delta 1.5, row["f"]
    assert_equal "text", row["t"]
    assert_nil row["n"]
    assert_equal "\x01\x02", row["b"]
  end

  def test_a_write_answers_with_the_rows_it_affected
    database.execute("create table tally (n integer)", [])

    assert_equal 3, database.execute("insert into tally values (1), (2), (3)", [])
  end

  def test_a_statement_carries_the_values_it_was_given
    database.execute("create table kinds (i integer, f real, t text, n text)", [])
    database.execute("insert into kinds values (?, ?, ?, ?)", [ 7, 2.5, "word", nil ])

    assert_equal [ { "i" => 7, "f" => 2.5, "t" => "word", "n" => nil } ],
                 database.query("select * from kinds", [])
  end

  def test_a_value_the_wire_cannot_carry_is_refused
    error = assert_raises(Workers::DatabaseError) { database.execute("select ?", [ Object.new ]) }

    assert_includes error.message, "Object"
  end

  # B-23: what the database said about the statement is the Tenant's own.
  def test_a_statement_the_database_refuses_carries_what_it_said
    error = assert_raises(Workers::DatabaseError) { database.query("select * from nowhere", []) }

    assert_includes error.message, "no such table: nowhere"
  end

  # B-19: a Tenant that declares a database gets one, without anything having
  # created it ahead of the statement that first needed it. Nothing here
  # creates it — `setup` made sure of the opposite.
  def test_a_database_nobody_created_is_there_for_the_first_statement
    assert_equal [], database.query("select 1 where 0", [])
  end

  def test_a_database_the_host_cannot_reach_is_recorded_for_the_operator
    errors = StringIO.new
    stranded = Workers::Hrana.new(url: "http://127.0.0.1:1", admin_url: "http://127.0.0.1:1",
                                  namespace: "stranded", errors: errors)

    error = assert_raises(Workers::DatabaseError) { stranded.query("select 1", []) }

    assert_includes errors.string, "127.0.0.1:1"
    refute_includes error.message, "127.0.0.1", "the address reached the Tenant"
  end

  # A database that refuses the connection fails at once; one that takes it
  # and then says nothing is what the invocation's own clock would otherwise
  # run out on, leaving the Worker cut short rather than able to rescue.
  def test_a_database_that_stops_answering_gives_up_before_the_invocation_would
    silent = Unresponsive.silent
    stranded = Workers::Hrana.new(url: "http://127.0.0.1:#{silent}", admin_url: "http://127.0.0.1:#{silent}",
                                  namespace: "stranded")

    at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Workers::DatabaseError) { stranded.query("select 1", []) }
    waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - at

    assert_operator waited, :<, Workers::Runtime.default.timeout,
                    "the statement outlasted what the invocation is allowed"
  end

  def test_a_database_that_declines_is_not_one_the_host_could_not_reach
    errors = StringIO.new
    busy = Workers::Hrana.new(url: "http://127.0.0.1:#{Unresponsive.declining(429)}", admin_url: "http://127.0.0.1:1",
                              namespace: "busy", errors: errors)

    assert_raises(Workers::DatabaseBusy) { busy.query("select 1", []) }
    refute_includes errors.string, "cannot reach"
  end

  private

  def database
    @database ||= Workers::Hrana.new(url: Sqld.url, admin_url: Sqld.admin_url, namespace: @namespace)
  end
end
