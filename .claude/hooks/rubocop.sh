#!/usr/bin/env bash
# Keep every Ruby file written during a turn within the project's style.
# What RuboCop can safely correct is corrected in place; only what a human
# must decide is handed back, so style never becomes a round trip.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root" || exit 0

file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

# Files outside the project carry no style of ours.
case "$file" in
  "$root"/*) ;;
  *) exit 0 ;;
esac

case "$file" in
  *.rb | *.rake | *.gemspec | */Rakefile | */Gemfile | */config.ru) ;;
  *) exit 0 ;;
esac

output=$(bundle exec rubocop --autocorrect --force-exclusion --format simple "$file" 2>&1) && exit 0

echo "$output" >&2
exit 2
