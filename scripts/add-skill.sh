#!/bin/sh
# add-skill.sh — vendor a third-party skill into this repository.
#
# Why copy rather than link: `npx skills` and friends install by symlinking an
# agent directory at a canonical copy elsewhere on the machine. Both tools' skill
# directories are symlinks *into this repository*, so such a link would be
# committed as a relative path that resolves to nothing on any other machine.
# Copying real files is what makes a skill survive a clone.
#
# Why here rather than a package manager: one copy under skills/ is visible to
# Claude Code and OpenCode at once, needs no install step, and travels with a
# plain `git pull`. The cost is that updates are explicit — hence --update.
#
# This script never stages, commits, or pushes. It prints the command and stops.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/backup.sh"

SKILLS_DIR="$AD_ROOT/skills"

usage() {
    cat <<'USAGE'
Usage: add-skill.sh SOURCE [--skill NAME] [--ref REF] [--force]
       add-skill.sh --update NAME [--force]
       add-skill.sh --list

  SOURCE       owner/repo, a git URL, or a local path to a skill package
  --skill NAME which skill to take, when the package holds more than one
  --ref REF    branch or tag to fetch (default: the package's default branch)
  --force      replace a skill that is already here (the old copy is backed up)
  --update     refetch a vendored skill from the source recorded in its .source
  --list       list the skills in this repository that came from elsewhere
  --help       this message

The skill is copied into skills/<name>/ as real files and is live in Claude Code
and OpenCode immediately — both read that directory through a symlink. Nothing
is committed; the command to do that yourself is printed at the end.
USAGE
}

# --- source resolution ------------------------------------------------------

# owner/repo is shorthand for GitHub, which is where skills are published in
# practice. Anything else is passed to git untouched, so a local path or a
# self-hosted URL works without a special flag.
resolve_source() {
    case "$1" in
        *://*|git@*)   printf '%s\n' "$1" ;;
        /*|./*|../*|~*) printf '%s\n' "$1" ;;
        */*)
            if [ -d "$1" ]; then
                printf '%s\n' "$1"
            else
                printf 'https://github.com/%s.git\n' "$1"
            fi
            ;;
        *) ad_die "cannot tell what '$1' is: use owner/repo, a git URL, or a path" ;;
    esac
}

fetch() {  # RESOLVED_SOURCE REF DEST
    if [ -d "$1" ]; then
        # A local clone with --depth is refused by git; the copy is cheap anyway.
        if [ -n "$2" ]; then
            git clone --quiet --branch "$2" "$1" "$3"
        else
            git clone --quiet "$1" "$3"
        fi
    elif [ -n "$2" ]; then
        git clone --quiet --depth 1 --branch "$2" "$1" "$3"
    else
        git clone --quiet --depth 1 "$1" "$3"
    fi
}

# --- locating the skill inside the package ----------------------------------

# The layouts seen in the wild, in the order the ecosystem uses them.
SEARCH_ROOTS='skills .agents/skills .claude/skills .'

locate_named() {  # CLONE NAME -> path relative to the clone
    for _r in $SEARCH_ROOTS; do
        _p=$(printf '%s/%s' "$_r" "$2" | sed 's|^\./||')
        if [ -f "$1/$_p/SKILL.md" ]; then
            printf '%s\n' "$_p"
            return 0
        fi
    done
    return 1
}

# With no --skill, a package holding exactly one skill is unambiguous and a
# package holding several is not. Guessing is worse than asking.
locate_only() {  # CLONE -> path relative to the clone
    if [ -f "$1/SKILL.md" ]; then printf '.\n'; return 0; fi
    _found=$(
        for _r in $SEARCH_ROOTS; do
            if [ -d "$1/$_r" ]; then
                for _d in "$1/$_r"/*/; do
                    if [ -f "$_d/SKILL.md" ]; then
                        printf '%s\n' "$(printf '%s' "${_d%/}" | sed "s|^$1/||")"
                    fi
                done
            fi
        done | sort -u
    )
    _n=$(printf '%s' "$_found" | grep -c . || true)
    if [ "$_n" -eq 1 ]; then
        printf '%s\n' "$_found"
        return 0
    fi
    if [ "$_n" -eq 0 ]; then
        ad_die "no SKILL.md found in that package"
    fi
    ad_warn "that package holds more than one skill; choose one with --skill NAME:"
    printf '%s\n' "$_found" | sed 's|.*/||; s/^/  /' >&2
    exit 1
}

# --- the vendoring itself ---------------------------------------------------

vendor() {  # RAW_SOURCE REF WANTED_NAME FORCE
    _raw=$1; _ref=$2; _want=$3; _force=$4
    _src=$(resolve_source "$_raw")

    _tmp=$(mktemp -d "${TMPDIR:-/tmp}/agent-dotfiles-skill.XXXXXX")
    # shellcheck disable=SC2064  # expand _tmp now, not when the trap fires
    trap "rm -rf '$_tmp'" EXIT INT TERM

    if ! fetch "$_src" "$_ref" "$_tmp/pkg" 2>/dev/null; then
        ad_die "could not fetch $_src${_ref:+ at $_ref}"
    fi

    if [ -n "$_want" ]; then
        _rel=$(locate_named "$_tmp/pkg" "$_want") \
            || ad_die "no skill named '$_want' in that package"
    else
        _rel=$(locate_only "$_tmp/pkg")
    fi

    if [ "$_rel" = "." ]; then
        _name=${_want:-$(basename -- "$(printf '%s' "$_raw" | sed 's|\.git$||; s|/$||')")}
    else
        _name=${_want:-$(basename -- "$_rel")}
    fi
    case "$_name" in
        ""|.|..|*/*) ad_die "refusing to write a skill named '$_name'" ;;
    esac

    _dest="$SKILLS_DIR/$_name"
    if [ -e "$_dest" ]; then
        if [ "$_force" -ne 1 ]; then
            ad_die "skills/$_name already exists. Re-run with --force to replace it (the current copy is backed up first), or use --update to refetch it from its recorded source."
        fi
        _slot=$(ad_backup_move "$(ad_timestamp)" "$_dest")
        ad_say "backed up the previous copy to $_slot"
    fi

    mkdir -p "$_dest"
    # tar rather than cp -R so the upstream .git, if the skill sits at the
    # package root, does not come along for the ride.
    ( cd "$_tmp/pkg/$_rel" && tar cf - --exclude .git . ) | ( cd "$_dest" && tar xf - )

    _sha=$(git -C "$_tmp/pkg" rev-parse HEAD)
    cat > "$_dest/.source" <<PROV
source: $_raw
ref: ${_ref:-(default branch)}
commit: $_sha
path: $_rel
name: $_name
fetched: $(ad_timestamp)
PROV

    rm -rf "$_tmp"
    trap - EXIT INT TERM

    ad_say "vendored $_name -> skills/$_name (from $_raw at ${_sha%"${_sha#???????}"})"
    ad_say "live now in Claude Code and OpenCode; no install step needed."
    ad_say ""
    ad_say "Nothing was staged. Yours to commit:"
    ad_say "  git -C $AD_ROOT add skills/$_name && git -C $AD_ROOT commit -m \"add $_name skill\""
}

prov_field() { sed -n "s/^$2: //p" "$1/.source" 2>/dev/null | head -1; }

cmd_update() {  # NAME
    _d="$SKILLS_DIR/$1"
    if [ ! -d "$_d" ]; then ad_die "no skill named '$1' in this repository"; fi
    if [ ! -f "$_d/.source" ]; then
        ad_die "skills/$1 has no .source, so it was written here rather than vendored. There is nothing upstream to update it from."
    fi
    _s=$(prov_field "$_d" source)
    _r=$(prov_field "$_d" ref)
    case "$_r" in "(default branch)") _r="" ;; esac
    if [ -z "$_s" ]; then ad_die "skills/$1/.source does not record a source"; fi
    vendor "$_s" "$_r" "$1" 1
}

cmd_list() {
    _any=0
    for _d in "$SKILLS_DIR"/*/; do
        if [ -f "$_d/.source" ]; then
            _any=1
            _n=$(basename -- "${_d%/}")
            ad_say "$_n  $(prov_field "${_d%/}" source)  $(prov_field "${_d%/}" commit | cut -c1-7)"
        fi
    done
    if [ "$_any" -eq 0 ]; then
        ad_say "no vendored skills; everything under skills/ was written here"
    fi
}

# --- argument handling ------------------------------------------------------

SOURCE=''; WANT=''; REF=''; FORCE=0; MODE='add'; UPDATE_NAME=''
while [ $# -gt 0 ]; do
    case "$1" in
        --skill)  shift; WANT=${1:-}; if [ -z "$WANT" ]; then ad_die "--skill needs a name"; fi ;;
        --ref)    shift; REF=${1:-};  if [ -z "$REF" ];  then ad_die "--ref needs a branch or tag"; fi ;;
        --force)  FORCE=1 ;;
        --update) MODE='update'; shift; UPDATE_NAME=${1:-}; if [ -z "$UPDATE_NAME" ]; then ad_die "--update needs a skill name"; fi ;;
        --list)   MODE='list' ;;
        -h|--help) usage; exit 0 ;;
        -*)       usage >&2; ad_die "unknown option: $1" ;;
        *)        if [ -n "$SOURCE" ]; then ad_die "more than one source given"; fi; SOURCE=$1 ;;
    esac
    shift
done

case "$MODE" in
    list)   cmd_list ;;
    update) cmd_update "$UPDATE_NAME" ;;
    add)
        if [ -z "$SOURCE" ]; then usage >&2; ad_die "a source is required"; fi
        vendor "$SOURCE" "$REF" "$WANT" "$FORCE"
        ;;
esac
