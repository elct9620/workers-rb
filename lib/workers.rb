# frozen_string_literal: true

require "kobako"

module Workers
  # Tenant code depends on JSON and ASCII Regexp, which the guest binary
  # bundled in the gem does not carry. `rake wasm:fetch` places the variant
  # that does alongside the gem it was built with.
  def self.default_guest_binary
    File.expand_path("../vendor/kobako+full-#{Kobako::VERSION}.wasm", __dir__)
  end
end

# Defined above the requires because `Host` reads the default while its class
# body runs.
require_relative "workers/databases"
require_relative "workers/environment"
require_relative "workers/failure"
require_relative "workers/guest"
require_relative "workers/manifest"
require_relative "workers/node"
require_relative "workers/runtime"
require_relative "workers/runtime_kit"
require_relative "workers/tenant"
require_relative "workers/host"
