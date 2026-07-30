# frozen_string_literal: true

module Workers
  # What every Sandbox the Host builds is configured with. One set applies to
  # every Tenant; a Manifest does not alter it.
  Runtime = Data.define(:guest_binary, :timeout, :memory_limit, :output_limit) do
    # kobako's own defaults are looser on every limit, so each is stated.
    def self.default(guest_binary: Workers.default_guest_binary)
      new(guest_binary: guest_binary, timeout: 5.0,
          memory_limit: 16 * 1024 * 1024, output_limit: 64 * 1024)
    end

    def sandbox
      Kobako::Sandbox.new(
        wasm_path: guest_binary,
        timeout: timeout,
        memory_limit: memory_limit,
        stdout_limit: output_limit,
        stderr_limit: output_limit,
        # Guest code runs in parallel across Puma's threads rather than
        # queueing behind whichever Tenant is slowest.
        gvl: :release
      )
    end
  end
end
