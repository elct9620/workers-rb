# frozen_string_literal: true

require "test_helper"
require "puma"
require "puma/configuration"

# How long the Host may take to stop. The server the suite does not start is
# the one that reads this, so what is checked here is the configuration it
# would read rather than a running stop.
class ShutdownTest < TestHelper::Case
  CONFIG = File.expand_path("../config/puma.rb", __dir__)
  SETTING = "WORKERS_SHUTDOWN_TIMEOUT"

  # Puma's own "wait forever", which `-1` is the value of.
  FOREVER = -1

  def test_the_wait_is_puma_s_own_when_nothing_names_a_bound
    assert_equal FOREVER, bound(nil)
  end

  def test_a_named_bound_is_what_the_host_waits
    assert_equal 10, bound("10")
  end

  # Zero is Puma's `:immediately`, which the chart offers and so must survive
  # the trip through the environment as a bound rather than as absent.
  def test_zero_bounds_the_wait_rather_than_removing_it
    assert_equal 0, bound("0")
  end

  # A Host that cannot read this setting is one whose stop is not what the
  # operator asked for, and the stop is the last moment to find that out.
  def test_a_setting_that_is_no_number_stops_the_host_from_starting
    assert_raises(ArgumentError) { bound("soon") }
  end

  private

  def bound(setting)
    was = ENV.fetch(SETTING, nil)
    setting.nil? ? ENV.delete(SETTING) : ENV[SETTING] = setting

    config = Puma::Configuration.new(config_files: [ CONFIG ])
    config.load
    config.clamp
    config.options[:force_shutdown_after]
  ensure
    was.nil? ? ENV.delete(SETTING) : ENV[SETTING] = was
  end
end
