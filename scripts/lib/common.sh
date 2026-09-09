# scripts/lib/common.sh — paths, logging, and failure handling.
# Sourced by every entry point. Nothing here touches the filesystem except
# ad_repo_revision, which only reads.
#
# Note: there is deliberately no ad_repo_root helper. Each entry point needs the
# repository root *before* it can source this file, so the three scripts inline
# `CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P` instead.
#
# Every path is reached through these accessors rather than by expanding $HOME
# directly, because that is what lets the tests sandbox them.

ad_die()  { printf 'agent-dotfiles: %s\n' "$*" >&2; exit 1; }
ad_warn() { printf 'agent-dotfiles: %s\n' "$*" >&2; }
ad_say()  { printf '%s\n' "$*"; }

ad_claude_home()   { printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }
ad_opencode_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"; }
ad_state_home()    { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles"; }
ad_config_home()   { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agent-dotfiles"; }

ad_timestamp() { date -u '+%Y-%m-%dT%H%M%SZ'; }

ad_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        ad_die "jq is required but not installed (brew install jq / apt install jq)"
    fi
}

ad_repo_revision() {
    if _r=$( cd "$1" 2>/dev/null && git rev-parse HEAD 2>/dev/null ); then
        printf '%s\n' "$_r"
    else
        printf 'unknown\n'
    fi
}
