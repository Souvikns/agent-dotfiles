#!/bin/sh
# sync.sh — the mechanics behind the /sync command in both tools.
#
# This script never writes git history. It reads the repository's state, tells
# you what has changed, hands you the commit command, and then fast-forwards and
# reinstalls. Committing is yours: an agent driving this script must not be able
# to author commits on your behalf, and the surest way to guarantee that is for
# the machinery to have no such capability at all.
#
# The corollary is that `pull` is genuinely read-mostly. It fast-forwards or it
# stops; it will not merge or rebase to resolve a divergence, because that is
# rewriting your history under a different name.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/machine.sh"

usage() {
    cat <<'USAGE'
Usage: sync.sh [status|pull]

  (no argument)  status, then pull — the everyday path
  status         machine, branch, remote, and uncommitted changes. Read-only.
  pull           git pull --ff-only, then install.sh --all
  --help         this message

Committing and pushing are deliberately absent. When there is something to
commit, `status` prints the command for you to run yourself.

Intended to be driven by the /sync command in Claude Code and OpenCode, but it
works on its own too.
USAGE
}

has_remote() { [ -n "$(git -C "$AD_ROOT" remote 2>/dev/null)" ]; }

require_repo() {
    if ! git -C "$AD_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        ad_die "$AD_ROOT is not a git repository"
    fi
}

cmd_status() {
    require_repo
    ad_say "repo:    $AD_ROOT"
    ad_say "machine: $(ad_machine_load 2>/dev/null || printf '(none recorded)')"
    ad_say "branch:  $(git -C "$AD_ROOT" branch --show-current)"

    if has_remote; then
        git -C "$AD_ROOT" fetch --quiet 2>/dev/null || ad_warn "could not reach the remote"
        _up=$(git -C "$AD_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || printf '')
        if [ -n "$_up" ]; then
            _ab=$(git -C "$AD_ROOT" rev-list --left-right --count "$_up...HEAD" 2>/dev/null || printf '0\t0')
            ad_say "remote:  $_up (behind $(printf '%s' "$_ab" | cut -f1), ahead $(printf '%s' "$_ab" | cut -f2))"
        else
            ad_say "remote:  configured, but this branch has no upstream"
        fi
    else
        ad_say "remote:  no remote configured — there is nothing to pull from yet"
    fi

    _dirty=$(git -C "$AD_ROOT" status --porcelain -uall)
    if [ -z "$_dirty" ]; then
        ad_say "changes: no local changes"
    else
        ad_say "changes:"
        printf '%s\n' "$_dirty" | sed 's/^/  /'
        ad_say ""
        ad_say "Nothing was staged. Yours to commit when you are ready:"
        ad_say "  git -C $AD_ROOT add -A && git -C $AD_ROOT commit -m \"...\""
    fi
}

cmd_pull() {
    require_repo
    if has_remote; then
        if ! git -C "$AD_ROOT" pull --ff-only; then
            ad_die "pull refused: the branch has diverged from its remote. Reconcile it yourself — this script will not merge or rebase on your behalf."
        fi
    else
        ad_say "no remote configured — skipping fetch, reinstalling from the local checkout"
    fi
    _rc=0
    "$AD_ROOT/scripts/install.sh" --all || _rc=$?
    if [ "$_rc" -eq 3 ]; then
        ad_warn "install refused one or more targets (see above). Nothing was overwritten."
    elif [ "$_rc" -ne 0 ]; then
        ad_die "install failed with status $_rc"
    fi
}

case "${1:-}" in
    "")         cmd_status; ad_say ""; cmd_pull ;;
    status)     cmd_status ;;
    pull)       cmd_pull ;;
    -h|--help)  usage ;;
    *)          usage >&2; ad_die "unknown subcommand: $1" ;;
esac
