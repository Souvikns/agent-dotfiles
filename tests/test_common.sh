#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

assert_eq "claude home honours CLAUDE_CONFIG_DIR" "$SB/home/.claude" "$(ad_claude_home)"
assert_eq "opencode home honours XDG_CONFIG_HOME" "$SB/home/.config/opencode" "$(ad_opencode_home)"
assert_eq "state home honours XDG_STATE_HOME" "$SB/home/.local/state/agent-dotfiles" "$(ad_state_home)"
assert_eq "config home honours XDG_CONFIG_HOME" "$SB/home/.config/agent-dotfiles" "$(ad_config_home)"

unset CLAUDE_CONFIG_DIR
assert_eq "claude home falls back to HOME" "$SB/home/.claude" "$(ad_claude_home)"

case "$(ad_timestamp)" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z)
        assert_eq "timestamp is UTC and filename-safe" "ok" "ok" ;;
    *)  assert_eq "timestamp is UTC and filename-safe" "ok" "$(ad_timestamp)" ;;
esac

assert_eq "repo revision of a non-repo is 'unknown'" "unknown" "$(ad_repo_revision "$SB")"

sandbox_rm "$SB"
