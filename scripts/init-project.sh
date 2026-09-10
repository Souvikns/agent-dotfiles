#!/bin/sh
# init-project.sh — scaffold project-level configuration for Claude Code and
# OpenCode in one pass.
#
# The layout is not a compromise between the two tools; it is what they actually
# read. Verified 2026-09-10 against Claude Code 2.1.236 and opencode 1.18.30 —
# see docs/superpowers/verification-2026-09-10.md for the probes.
#
#   CLAUDE.md            read by BOTH. Claude Code loads it as project memory;
#                        OpenCode globs up for AGENTS.md, CLAUDE.md, CONTEXT.md.
#   .claude/rules/*.md   read by BOTH. Claude Code loads the directory natively;
#                        OpenCode reaches it through the instructions glob that
#                        the generated opencode.json declares.
#   .claude/skills/      read by BOTH, natively, with no configuration at all.
#                        OpenCode looks in .opencode/skills, .claude/skills and
#                        .agents/skills, so one directory serves both tools.
#   .claude/agents/      Claude Code only.
#   .claude/commands/    Claude Code only.
#   .opencode/agent/     OpenCode only.
#   .opencode/command/   OpenCode only.
#
# Agents and commands get one directory per tool on purpose. OpenCode refuses to
# start when an agent file carries Claude Code's `tools: Read, Grep` string form
# ("Expected object | undefined"), so a shared agent directory would break one
# tool the moment the other's conventions were used in it. Commands would in fact
# survive a symlink — OpenCode ignores argument-hint and allowed-tools — but a
# symlinked directory inside a project is a trap for anyone cloning it, and the
# saving is two files.
#
# Additive by design: an existing file is reported and left exactly as it is.
# This script never stages, commits, or pushes; it prints the command and stops.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"

RULES_GLOB='.claude/rules/*.md'

usage() {
    cat <<'USAGE'
Usage: init-project.sh [DIR] [--settings] [--mcp] [--dry-run]

  DIR          project to scaffold (default: the current directory)
  --settings   also write .claude/settings.json, a starter for shared project
               settings such as permissions
  --mcp        also write .mcp.json, Claude Code's project MCP server file
  --dry-run    print what would happen, write nothing
  --help       this message

Writes the project-level configuration both tools read. Nothing that already
exists is touched, so this is safe to re-run on a project that has half of it.
USAGE
}

# --- reporting --------------------------------------------------------------

CREATED=0
SKIPPED=0

report() {  # STATUS PATH
    if [ "$DRY_RUN" -eq 1 ] && [ "$1" = "created" ]; then
        ad_say "would create  $2"
    elif [ "$1" = "created" ]; then
        ad_say "created  $2"
    else
        ad_say "skipped  $2 (exists)"
    fi
}

# --- writers ----------------------------------------------------------------

# A directory is only useful to either tool once it survives a clone, and Git
# does not track empty directories — hence the .gitkeep.
mk_dir() {  # RELATIVE_PATH
    _p="$DIR/$1"
    if [ -d "$_p" ]; then
        SKIPPED=$((SKIPPED + 1)); report skipped "$1/"
        return 0
    fi
    CREATED=$((CREATED + 1)); report created "$1/"
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi
    mkdir -p "$_p"
    : > "$_p/.gitkeep"
}

# Content arrives on stdin. It is consumed either way, so a heredoc feeding a
# file that already exists cannot leave the script blocked on a full pipe.
mk_file() {  # RELATIVE_PATH
    _p="$DIR/$1"
    if [ -e "$_p" ]; then
        cat >/dev/null
        SKIPPED=$((SKIPPED + 1)); report skipped "$1"
        return 0
    fi
    CREATED=$((CREATED + 1)); report created "$1"
    if [ "$DRY_RUN" -eq 1 ]; then cat >/dev/null; return 0; fi
    mkdir -p "$(dirname -- "$_p")"
    cat > "$_p"
}

# --- the one thing that needs inspecting rather than writing ----------------

# OpenCode reads .claude/rules only because opencode.json points at it. When the
# project already has its own config, that file is the user's, so this reports
# the missing glob rather than editing around them.
check_instructions() {  # EXISTING_CONFIG_RELATIVE_PATH
    if ! command -v jq >/dev/null 2>&1; then
        ad_warn "$1 exists and jq is not installed, so its instructions could not be checked; make sure it lists \"$RULES_GLOB\""
        return 0
    fi
    if jq -e --arg g "$RULES_GLOB" '(.instructions // []) | index($g)' "$DIR/$1" >/dev/null 2>&1
    then
        return 0
    fi
    ad_warn "$1 does not list \"$RULES_GLOB\" in its instructions, so OpenCode will not read .claude/rules. Add it with:"
    ad_warn "  jq '.instructions = ((.instructions // []) + [\"$RULES_GLOB\"])' $1 > tmp && mv tmp $1"
}

# --- argument handling ------------------------------------------------------

DIR=''; DRY_RUN=0; WANT_SETTINGS=0; WANT_MCP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)  DRY_RUN=1 ;;
        --settings) WANT_SETTINGS=1 ;;
        --mcp)      WANT_MCP=1 ;;
        -h|--help)  usage; exit 0 ;;
        -*)         usage >&2; ad_die "unknown option: $1" ;;
        *)          if [ -n "$DIR" ]; then ad_die "more than one directory given"; fi; DIR=$1 ;;
    esac
    shift
done

if [ -z "$DIR" ]; then DIR=$PWD; fi
if [ ! -d "$DIR" ]; then ad_die "not a directory: $DIR"; fi
DIR=$(CDPATH= cd -- "$DIR" && pwd -P)

# The home directory is a real target for the *global* configuration this
# repository installs, and scaffolding a project on top of it would put a
# second, conflicting CLAUDE.md in the search path of both tools. Both sides are
# resolved first: on macOS $HOME is under /var, which is a symlink to /private/var,
# so a raw string comparison would miss.
_home=$(CDPATH= cd -- "$HOME" 2>/dev/null && pwd -P) || _home=$HOME
if [ "$DIR" = "$_home" ]; then
    ad_die "refusing to scaffold a project in the home directory; global configuration is what install.sh writes"
fi

# --- scaffold ---------------------------------------------------------------

ad_say "Scaffolding project configuration in $DIR"
ad_say ""

mk_file CLAUDE.md <<'DOC'
# Project instructions

Read by Claude Code as project memory, and by OpenCode, which looks for
`AGENTS.md`, `CLAUDE.md`, and `CONTEXT.md` on its way up to the repository root.
Keep it to what an agent needs and cannot infer: how to build, how to test, and
the conventions that are not visible in the code.

Longer, topic-shaped guidance belongs in `.claude/rules/` — one file per topic.
Both tools read that directory: Claude Code natively, OpenCode through the
`instructions` glob in `opencode.json`.

## Build and test

<!-- The commands an agent should run, and when to run them. -->

## Conventions

<!-- What to match: naming, layout, error handling, anything easy to get wrong. -->
DOC

if [ -f "$DIR/opencode.jsonc" ]; then
    SKIPPED=$((SKIPPED + 1)); report skipped opencode.jsonc
    check_instructions opencode.jsonc
elif [ -f "$DIR/opencode.json" ]; then
    SKIPPED=$((SKIPPED + 1)); report skipped opencode.json
    check_instructions opencode.json
else
    # A relative instructions pattern is globbed up from the session directory to
    # the worktree root, not resolved against the file that declares it, so this
    # keeps working from any subdirectory of the project.
    mk_file opencode.json <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "instructions": ["$RULES_GLOB"]
}
JSON
fi

mk_dir .claude/rules
mk_dir .claude/skills
mk_dir .claude/agents
mk_dir .claude/commands
mk_dir .opencode/agent
mk_dir .opencode/command

if [ "$WANT_SETTINGS" -eq 1 ]; then
    # Shared project settings, committed. Anything personal belongs in
    # .claude/settings.local.json, which Claude Code reads at higher precedence
    # and which should stay out of the repository.
    mk_file .claude/settings.json <<'JSON'
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
JSON
fi

if [ "$WANT_MCP" -eq 1 ]; then
    # Claude Code only. OpenCode declares its MCP servers under the "mcp" key of
    # opencode.json instead, in a different shape, so this file does not travel.
    mk_file .mcp.json <<'JSON'
{
  "mcpServers": {}
}
JSON
fi

# --- what to do next --------------------------------------------------------

ad_say ""
if [ "$DRY_RUN" -eq 1 ]; then
    ad_say "$CREATED to create, $SKIPPED already present. Nothing was written."
    exit 0
fi
ad_say "$CREATED created, $SKIPPED already present."

if [ "$CREATED" -eq 0 ]; then exit 0; fi

ad_say ""
ad_say "Shared by both tools:      CLAUDE.md, .claude/rules/, .claude/skills/"
ad_say "Claude Code only:          .claude/agents/, .claude/commands/"
ad_say "OpenCode only:             .opencode/agent/, .opencode/command/"

if [ ! -d "$DIR/.git" ] && ! git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    ad_say ""
    ad_warn "this is not a Git repository; OpenCode stops its search for project files at the worktree root, so it will treat this directory as the boundary"
    exit 0
fi

ad_say ""
ad_say "Nothing was staged. Yours to commit:"
ad_say "  git -C $DIR add CLAUDE.md opencode.json .claude .opencode && git -C $DIR commit -m \"add project agent configuration\""
if [ "$WANT_SETTINGS" -eq 1 ]; then
    ad_say ""
    ad_say "Consider ignoring your personal overrides:"
    ad_say "  echo '.claude/settings.local.json' >> $DIR/.gitignore"
fi
