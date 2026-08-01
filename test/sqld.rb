# frozen_string_literal: true

require "fileutils"
require "net/http"
require "socket"
require "tmpdir"

# The database server the suite drives.
#
# Started on the first test that needs a database and shared by the rest, so
# a run that only exercises routing pays nothing for it, and the Binding is
# proved against the server the cluster runs rather than a stand-in that
# could drift from it.
module Sqld
  # The suite is what the server exists for, so the suite is where the version
  # it drives is named. `rake sqld:fetch` reads it from here, which is what
  # keeps the binary in `vendor/` and the one these tests expect the same one.
  VERSION = "0.24.32"

  # A runner killed outright ends the server through neither `at_exit` nor
  # the trap. This is what still ends it, and it bounds how long a server
  # nobody owns can hold a port. It has to outlast the quietest stretch of a
  # run as well, or the server would leave in the middle of one.
  IDLE_SHUTDOWN = 120

  # Long enough that a machine under load still comes up, short enough that a
  # server which will never listen is reported rather than waited on.
  STARTUP = 30
  SHUTDOWN = 10

  LOCK = Mutex.new
  private_constant :LOCK

  class << self
    # Where the Host reaches the Tenants' databases.
    def url = running.fetch(:url)

    # Where the Host creates one that does not exist yet.
    def admin_url = running.fetch(:admin_url)

    # A namespace the suite is finished with. Left behind, it would be the
    # next test's starting state rather than an empty database.
    def drop(namespace)
      admin(Net::HTTP::Delete.new("/v1/namespaces/#{namespace}"))
    end

    private

    # A suite that drives concurrent invocations reaches here from more than
    # one thread, and two servers started for one run is one left behind.
    def running = LOCK.synchronize { @running ||= start }

    def start
      binary = executable
      dir = Dir.mktmpdir("workers-sqld")
      http = free_port
      admin = free_port
      pid = spawn(binary, dir, http, admin)

      arrange_shutdown(pid, dir)
      await(pid, dir, admin)

      { url: "http://127.0.0.1:#{http}", admin_url: "http://127.0.0.1:#{admin}" }
    end

    def executable
      path = File.expand_path("../vendor/sqld-#{VERSION}", __dir__)
      raise "no database server at #{path} — `rake sqld:fetch` first" unless File.executable?(path)

      path
    end

    # Asked of the operating system rather than chosen, so a suite running
    # beside another does not take a port it is already listening on.
    def free_port
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1]
    ensure
      server&.close
    end

    def spawn(binary, dir, http, admin)
      Process.spawn(
        binary,
        "--db-path", dir,
        "--http-listen-addr", "127.0.0.1:#{http}",
        "--admin-listen-addr", "127.0.0.1:#{admin}",
        "--enable-namespaces",
        # A request naming no namespace means the Host resolved a Binding to
        # nothing; answering it out of a shared default would hide that.
        "--disable-default-namespace",
        "--no-welcome",
        "--idle-shutdown-timeout-s", IDLE_SHUTDOWN.to_s,
        out: log_path(dir), err: [ :child, :out ],
        # Its own group, so what stops the server stops whatever it started.
        pgroup: true
      )
    end

    # Three layers, because each covers what the ones before it cannot: the
    # trap for a run that is asked to stop, `at_exit` for one that ends on its
    # own or on an exception — which is also where an interrupt arrives, since
    # it unwinds — and sqld's own idle timeout for a runner that is killed
    # outright and leaves the server with no one to end it.
    def arrange_shutdown(pid, dir)
      at_exit { stop(pid, dir) }
      Signal.trap("TERM") do
        stop(pid, dir)
        exit!(1)
      end
    end

    # Spawned is not listening, and listening is not yet answering.
    def await(pid, dir, admin)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + STARTUP
      begin
        Net::HTTP.get_response(URI("http://127.0.0.1:#{admin}/v1/namespaces"))
      rescue SystemCallError, IOError, Net::OpenTimeout
        raise "the database server did not come up:\n#{File.read(log_path(dir))}" unless
          alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

        sleep 0.1
        retry
      end
    end

    # A server that ended on its own — its idle timeout, or a crash — has
    # nothing left to signal, but a process nobody has waited on is still
    # something left behind. Both ways of saying "already gone" lead to the
    # same reaping.
    def stop(pid, dir)
      Process.kill("TERM", -pid)
      reap(pid)
    rescue Errno::ESRCH, Errno::EPERM
      reap(pid)
    ensure
      FileUtils.remove_entry(dir, true)
    end

    # Asked first and told second: a server given no chance to close its
    # files is one the next run has to recover. Told only while it is still
    # running — a pid the operating system has taken back names whatever it
    # hands out next.
    def reap(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SHUTDOWN
      loop do
        return if Process.waitpid(pid, Process::WNOHANG)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.05
      end

      Process.kill("KILL", -pid)
      Process.waitpid(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def alive?(pid)
      Process.waitpid(pid, Process::WNOHANG).nil?
    rescue Errno::ECHILD
      false
    end

    def log_path(dir) = File.join(dir, "sqld.log")

    def admin(request)
      address = URI(admin_url)
      Net::HTTP.start(address.host, address.port) { |http| http.request(request) }
    end
  end
end
