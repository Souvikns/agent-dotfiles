#!/bin/sh
# tests/test_harness.sh — the harness must be trustworthy before anything uses it.
set -u
. ./helpers.sh
. ./sandbox.sh

assert_eq   "assert_eq matches equal strings" "a" "a"
assert_ok   "assert_ok accepts a succeeding command" true
assert_fail "assert_fail accepts a failing command" false

SB=$(sandbox_new)
eval "$(sandbox_env "$SB")"
assert_eq   "sandbox redirects HOME" "$SB/home" "$HOME"
assert_eq   "sandbox redirects CLAUDE_CONFIG_DIR" "$SB/home/.claude" "$CLAUDE_CONFIG_DIR"
assert_file "sandbox created config home" "$XDG_CONFIG_HOME"
sandbox_rm "$SB"
assert_fail "sandbox_rm refuses a non-sandbox path" sandbox_rm /tmp
