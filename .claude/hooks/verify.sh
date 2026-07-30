#!/usr/bin/env bash
# A turn is not finished until the whole project still lints and passes.
# Refusing to stop keeps the failure and the change that caused it in the
# same turn, where the context to fix it is still at hand.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root" || exit 0

# Blocking twice would loop forever on a failure this hook cannot fix.
[ "$(jq -r '.stop_hook_active // false')" = "true" ] && exit 0

if ! output=$(bundle exec rubocop --format simple 2>&1); then
  echo "$output" >&2
  exit 2
fi

if ! output=$(bundle exec rake test 2>&1); then
  echo "$output" >&2
  exit 2
fi

exit 0
