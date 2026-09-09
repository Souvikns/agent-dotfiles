# tests/sandbox.sh — isolate every path the installer touches.
# Sourced, not executed. Callers must `eval` the block sandbox_env prints.

sandbox_new() {
    _sb=$(mktemp -d "${TMPDIR:-/tmp}/agent-dotfiles-sb.XXXXXX") || return 1
    mkdir -p "$_sb/home" "$_sb/home/.config" "$_sb/home/.local/state"
    printf '%s\n' "$_sb"
}

sandbox_env() {
    # $1 = sandbox dir. Prints an eval-able export block.
    cat <<ENV
HOME='$1/home'
CLAUDE_CONFIG_DIR='$1/home/.claude'
XDG_CONFIG_HOME='$1/home/.config'
XDG_STATE_HOME='$1/home/.local/state'
export HOME CLAUDE_CONFIG_DIR XDG_CONFIG_HOME XDG_STATE_HOME
ENV
}

sandbox_rm() {
    # Guarded so a caller bug cannot turn this into `rm -rf $HOME`.
    case "$1" in
        */agent-dotfiles-sb.*) rm -rf "$1" ;;
        *) echo "refusing to remove non-sandbox path: $1" >&2; return 1 ;;
    esac
}
