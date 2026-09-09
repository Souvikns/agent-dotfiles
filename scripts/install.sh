#!/bin/sh
# install.sh — link this repository into OpenCode's and Claude Code's global
# configuration directories.
#
# Never makes a network request, installs a package, or edits a shell startup
# file. Repository root is derived from this script's own resolved path.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/machine.sh"
. "$AD_ROOT/scripts/lib/targets.sh"
. "$AD_ROOT/scripts/lib/backup.sh"
. "$AD_ROOT/scripts/lib/manifest.sh"
. "$AD_ROOT/scripts/lib/link.sh"
. "$AD_ROOT/scripts/lib/settings.sh"

usage() {
    cat <<'USAGE'
Usage: install.sh (--claude | --opencode | --all) [options]

Components (at least one required):
  --claude          link Claude Code files and generate its settings
  --opencode        link OpenCode files
  --all             both

Options:
  --machine NAME    name this machine; required on first run, remembered after
  --dry-run         print every planned operation, change nothing
  --force           back up and replace a conflicting target
  --clean           regenerate settings.json from repository layers only,
                    discarding keys that exist solely in the live file
  --hook            install a git post-merge hook so a pull re-runs this script
  --help            this message

Safety:
  A target that is a real file, a real directory, or a symlink owned by
  something else is REFUSED, not overwritten. Use --force to back it up under
  $XDG_STATE_HOME/agent-dotfiles/backups and replace it. Rerunning with no
  changes creates no backups and rewrites nothing.

Exit codes: 0 ok, 1 usage or fatal error, 3 one or more targets refused.
USAGE
}

do_claude=0; do_opencode=0; force=0; dry=0; clean=0; hook=0; machine=''
while [ $# -gt 0 ]; do
    case $1 in
        --claude)     do_claude=1 ;;
        --opencode)   do_opencode=1 ;;
        --all)        do_claude=1; do_opencode=1 ;;
        --machine)    shift; machine=${1:-} ;;
        --machine=*)  machine=${1#--machine=} ;;
        --dry-run)    dry=1 ;;
        --force)      force=1 ;;
        --clean)      clean=1 ;;
        --hook)       hook=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            usage >&2; ad_die "unknown option: $1" ;;
    esac
    shift
done

if [ "$do_claude" -eq 0 ] && [ "$do_opencode" -eq 0 ]; then
    usage >&2
    ad_die "choose --claude, --opencode, or --all"
fi

ad_require_jq

# A dry run must change nothing at all, including the recorded machine name,
# so validate the given name rather than saving it.
if [ "$dry" -eq 1 ] && [ -n "$machine" ]; then
    if ! ad_machine_valid "$machine"; then
        ad_die "invalid machine name '$machine'"
    fi
else
    machine=$(ad_machine_resolve "$machine")
fi
ts=$(ad_timestamp)

if [ "$dry" -eq 1 ]; then ad_say "dry run — nothing will change"; fi
ad_say "machine: $machine"
ad_say "repo:    $AD_ROOT"

if [ "$dry" -eq 0 ]; then ad_manifest_init "$AD_ROOT" "$machine"; fi

rowfile=$(mktemp "${TMPDIR:-/tmp}/agent-dotfiles-rows.XXXXXX")
trap 'rm -f "$rowfile"' EXIT INT TERM
{
    if [ "$do_claude" -eq 1 ];   then ad_targets_claude; fi
    if [ "$do_opencode" -eq 1 ]; then ad_targets_opencode "$machine"; fi
} > "$rowfile"

refused=0
# Read from a file, not a pipe: a pipeline would run this loop in a subshell and
# the refusal counter would be lost.
while IFS= read -r row; do
    kind=$(ad_row_kind "$row")
    src="$AD_ROOT/$(ad_row_source "$row")"
    tgt=$(ad_row_target "$row")

    if [ "$kind" = "gen" ]; then
        ad_settings_write "$AD_ROOT" "$machine" "$tgt" "$clean" "$dry"
        ad_say "  generate  $tgt"
        if [ "$dry" -eq 0 ]; then ad_manifest_add gen "$src" "$tgt" ""; fi
        continue
    fi

    rc=0
    out=$(ad_link_apply "$src" "$tgt" "$force" "$dry" "$ts") || rc=$?
    action=$(printf '%s' "$out" | cut -d' ' -f1)
    detail=$(printf '%s' "$out" | cut -s -d' ' -f2)

    case $rc in
        0)  ad_say "  $action    $tgt"
            if [ "$dry" -eq 0 ]; then ad_manifest_add "$kind" "$src" "$tgt" "$detail"; fi ;;
        3)  refused=$((refused + 1))
            ad_warn "  refuse    $tgt ($detail) — rerun with --force to back it up and replace it" ;;
        4)  ad_warn "  skip      $tgt (source missing: $src)" ;;
        *)  ad_die "unexpected failure linking $tgt" ;;
    esac
done < "$rowfile"

if [ "$hook" -eq 1 ] && [ "$dry" -eq 0 ]; then
    if [ -d "$AD_ROOT/.git" ]; then
        cat > "$AD_ROOT/.git/hooks/post-merge" <<'HOOK'
#!/bin/sh
# Installed by agent-dotfiles install.sh --hook.
# Regenerates settings after a pull, so `git pull` is the whole update workflow.
exec "$(git rev-parse --show-toplevel)/scripts/install.sh" --all
HOOK
        chmod +x "$AD_ROOT/.git/hooks/post-merge"
        ad_say "installed post-merge hook: git pull now re-runs this installer"
    else
        ad_warn "not a git clone; skipped --hook"
    fi
fi

cat <<SHELL

Add these two lines to your shell startup file if they are not there already.
They are identical on every machine, and this installer will not edit the file
for you:

  [ -f "\$HOME/.config/agent-dotfiles/env" ] && . "\$HOME/.config/agent-dotfiles/env"
  export OPENCODE_CONFIG="\$HOME/.config/opencode/machine.json"
SHELL

if [ "$refused" -gt 0 ]; then
    ad_warn ""
    ad_warn "$refused target(s) refused. Nothing was overwritten."
    exit 3
fi
