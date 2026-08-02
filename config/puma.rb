# frozen_string_literal: true

# How long a request still running may hold up a Host that was told to stop.
#
# Puma waits for it forever unless told otherwise, and this file keeps that
# rather than choosing for every Host: whether a request here can outlive its
# own work depends on what the shared directory is mounted from, which is the
# operator's to know. Naming a bound is the chart's, and SPEC.md E-14 is the
# state that makes one worth naming.
force_shutdown_after ENV.fetch("WORKERS_SHUTDOWN_TIMEOUT", -1)

# What a Host does with the connections already waiting to be accepted when it
# is told to stop.
#
# Leaving the Service and being told to stop reach a Host in no order, so some
# connections arrive after the decision and before the news of it. Puma drops
# them by default, and each one is a reset rather than a response — so they
# are taken and answered, which asks nothing of the operator and needs no
# guess at how long the news takes. What arrives after the last of them is
# refused, which is what the Gateway retries.
drain_on_shutdown true
