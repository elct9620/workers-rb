# frozen_string_literal: true

# How long a request still running may hold up a Host that was told to stop.
#
# Puma waits for it forever unless told otherwise, and this file keeps that
# rather than choosing for every Host: whether a request here can outlive its
# own work depends on what the shared directory is mounted from, which is the
# operator's to know. Naming a bound is the chart's, and SPEC.md E-14 is the
# state that makes one worth naming.
force_shutdown_after ENV.fetch("WORKERS_SHUTDOWN_TIMEOUT", -1)
