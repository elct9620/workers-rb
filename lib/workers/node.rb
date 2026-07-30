# frozen_string_literal: true

require "socket"

module Workers
  # The cluster node this Host runs on, as tenant code reads it through `Env`.
  #
  # The Writer designation comes from configuration rather than from node
  # state: the replicated filesystem's lease does not move on its own, and the
  # marker it leaves behind is absent both when this node is the Writer and
  # when it cannot tell — so asking the operator is the only unambiguous answer.
  Node = Data.define(:name, :writer) do
    def self.current(env = ENV)
      new(name: Socket.gethostname, writer: env.fetch("WORKERS_WRITER", "false") == "true")
    end

    def writer? = writer
  end
end
