#!/bin/sh
# sync.sh — the mechanics behind the /sync command in both tools.
#
# Deliberately split into small subcommands rather than one do-everything run:
# the agent calls `status` first, shows you the result, and only then decides
# whether to `push`. That confirmation step is the reason /sync exists at all
# rather than a shell alias.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/machine.sh"

usage() {
    cat <<'USAGE'
Usage: sync.sh <status|push MESSAGE|pull>

  status         machine, branch, remote, and uncommitted changes. Read-only.
  push MESSAGE   stage everything, commit with MESSAGE, push if a remote exists
  pull           git pull --ff-only, then install.sh --all
  --help         this message

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
        ad_say "remote:  no remote configured — push and pull will do nothing"
    fi

    _dirty=$(git -C "$AD_ROOT" status --porcelain -uall)
    if [ -z "$_dirty" ]; then
        ad_say "changes: no local changes"
    else
        ad_say "changes:"
        printf '%s\n' "$_dirty" | sed 's/^/  /'
    fi
}

cmd_push() {
    require_repo
    if [ -z "${1:-}" ]; then
        usage >&2
        ad_die "push needs a commit message"
    fi
    if [ -z "$(git -C "$AD_ROOT" status --porcelain -uall)" ]; then
        ad_say "nothing to commit"
    else
        git -C "$AD_ROOT" add -A
        # Commit signing prompts for a passphrase, which cannot happen when an
        # agent runs this. Say so plainly instead of failing cryptically.
        if ! git -C "$AD_ROOT" commit -m "$1"; then
            ad_die "commit failed. If this repository signs commits, the GPG passphrase prompt cannot appear here — run the commit yourself in a terminal, or set commit.gpgsign=false for this repository."
        fi
    fi
    if has_remote; then
        git -C "$AD_ROOT" push
    else
        ad_warn "no remote configured; the commit is local only"
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
    status)     cmd_status ;;
    push)       shift; cmd_push "${1:-}" ;;
    pull)       cmd_pull ;;
    -h|--help)  usage ;;
    *)          usage >&2; ad_die "unknown subcommand: ${1:-(none)}" ;;
esac
