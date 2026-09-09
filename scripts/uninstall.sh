#!/bin/sh
# uninstall.sh — remove only what this repository installed, and only when the
# target still matches the manifest.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/backup.sh"
. "$AD_ROOT/scripts/lib/manifest.sh"
. "$AD_ROOT/scripts/lib/link.sh"

usage() {
    cat <<'USAGE'
Usage: uninstall.sh [options]

  --dry-run   print what would be removed, change nothing
  --force     remove targets that no longer match the manifest, and remove the
              generated settings.json
  --restore   after removing, move backed-up originals back into place
  --help      this message

Removes only targets recorded in the manifest whose current state still matches
it. A target someone else has changed is refused, so an unrelated file is never
deleted. The generated settings.json is kept by default: it holds settings
Claude Code wrote for itself that exist nowhere else.

Exit codes: 0 ok, 1 fatal, 3 one or more targets refused.
USAGE
}

dry=0; force=0; restore=0
while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) dry=1 ;;
        --force)   force=1 ;;
        --restore) restore=1 ;;
        -h|--help) usage; exit 0 ;;
        *)         usage >&2; ad_die "unknown option: $1" ;;
    esac
    shift
done

ad_require_jq
if [ ! -f "$(ad_manifest_path)" ]; then
    ad_die "no manifest at $(ad_manifest_path); nothing was installed by this repository"
fi

rowfile=$(mktemp "${TMPDIR:-/tmp}/agent-dotfiles-un.XXXXXX")
trap 'rm -f "$rowfile"' EXIT INT TERM
ad_manifest_targets > "$rowfile"

refused=0
while IFS='|' read -r kind src tgt bak; do
    if [ -z "${tgt:-}" ]; then continue; fi

    if [ "$kind" = "gen" ]; then
        if [ "$force" -eq 1 ]; then
            if [ "$dry" -eq 0 ]; then rm -f "$tgt"; fi
            ad_say "  remove    $tgt (generated)"
        else
            ad_say "  keep      $tgt (generated; holds settings Claude Code wrote — use --force to remove)"
        fi
        continue
    fi

    state=$(ad_link_state "$tgt" "$src")
    case $state in
        ok)
            if [ "$dry" -eq 0 ]; then rm -f "$tgt"; fi
            ad_say "  remove    $tgt" ;;
        missing)
            ad_say "  absent    $tgt" ;;
        *)
            if [ "$force" -eq 1 ]; then
                if [ "$dry" -eq 0 ]; then rm -rf "$tgt"; fi
                ad_say "  remove    $tgt (forced, was $state)"
            else
                refused=$((refused + 1))
                ad_warn "  refuse    $tgt (is $state, not ours) — use --force to remove it anyway"
            fi ;;
    esac

    if [ "$restore" -eq 1 ] && [ -n "${bak:-}" ] && [ "$dry" -eq 0 ]; then
        if ad_backup_restore "$bak" "$tgt"; then
            ad_say "  restore   $tgt"
        else
            ad_warn "  restore failed for $tgt (backup missing, or target still present)"
        fi
    fi
done < "$rowfile"

if [ "$refused" -gt 0 ]; then
    ad_warn ""
    ad_warn "$refused target(s) refused. Nothing unrelated was deleted."
    exit 3
fi
