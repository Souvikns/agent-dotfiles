#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

# The working tree, not the last commit: the script under test is the one on disk.
cp -R "$REPO" "$HOME/.agent-dotfiles"
rm -rf "$HOME/.agent-dotfiles/.git"
INIT="$HOME/.agent-dotfiles/scripts/init-project.sh"

assert_ok   "--help works" sh "$INIT" --help
assert_fail "an unknown option fails" sh "$INIT" --bogus
assert_fail "a missing directory fails" sh "$INIT" "$SB/nosuch"
assert_fail "two directories fail" sh "$INIT" "$SB" "$SB"

# Scaffolding the home directory would put a second CLAUDE.md in the search path
# of both tools, competing with the global configuration install.sh writes.
assert_fail "refuses to scaffold the home directory" sh "$INIT" "$HOME"

# --- dry run writes nothing -------------------------------------------------

P="$SB/proj"; mkdir -p "$P"; git -C "$P" init -q
out=$(sh "$INIT" "$P" --dry-run 2>&1)
assert_eq "dry run says it would create" "1" "$(printf '%s' "$out" | grep -c 'would create  CLAUDE.md')"
assert_eq "dry run wrote nothing" "0" \
    "$(find "$P" -mindepth 1 -not -path "$P/.git/*" -not -name .git | wc -l | tr -d ' ')"

# --- the scaffold itself ----------------------------------------------------

assert_ok "scaffolds a project" sh "$INIT" "$P"

assert_file "CLAUDE.md, read by both tools"          "$P/CLAUDE.md"
assert_file "opencode.json, read by OpenCode"        "$P/opencode.json"
assert_file "shared rules directory"                 "$P/.claude/rules"
assert_file "shared skills directory"                "$P/.claude/skills"
assert_file "Claude Code agents directory"           "$P/.claude/agents"
assert_file "Claude Code commands directory"         "$P/.claude/commands"
assert_file "OpenCode agent directory"               "$P/.opencode/agent"
assert_file "OpenCode command directory"             "$P/.opencode/command"

# Git does not track empty directories, so without these the layout does not
# survive the clone it exists to be shared through.
assert_file "rules survive a clone"    "$P/.claude/rules/.gitkeep"
assert_file "skills survive a clone"   "$P/.claude/skills/.gitkeep"
assert_file "OpenCode dirs survive a clone" "$P/.opencode/command/.gitkeep"

# The single wire between the two tools: without this glob OpenCode never reads
# .claude/rules, and a rule file would load in one tool and silently not the other.
if command -v jq >/dev/null 2>&1; then
    assert_ok "opencode.json is valid JSON" jq empty "$P/opencode.json"
    assert_eq "opencode.json points OpenCode at the shared rules" ".claude/rules/*.md" \
        "$(jq -r '.instructions[0]' "$P/opencode.json")"
    assert_eq "opencode.json declares the schema" "https://opencode.ai/config.json" \
        "$(jq -r '."$schema"' "$P/opencode.json")"
fi

# Not part of the default scaffold: one is Claude-Code-only, the other is a stub
# that most projects never fill in.
assert_eq "no settings.json unless asked" "0" "$([ -e "$P/.claude/settings.json" ] && echo 1 || echo 0)"
assert_eq "no .mcp.json unless asked"     "0" "$([ -e "$P/.mcp.json" ] && echo 1 || echo 0)"

# --- additive, not idempotent-by-overwrite ----------------------------------

printf 'edited by hand\n' > "$P/CLAUDE.md"
out=$(sh "$INIT" "$P" 2>&1)
assert_eq "a second run creates nothing" "1" "$(printf '%s' "$out" | grep -c '^0 created')"
assert_eq "a second run reports what was there" "1" "$(printf '%s' "$out" | grep -c 'skipped  CLAUDE.md (exists)')"
assert_eq "an edited file is left alone" "edited by hand" "$(cat "$P/CLAUDE.md")"

# --- the optional files -----------------------------------------------------

assert_ok "writes settings.json on request" sh "$INIT" "$P" --settings
assert_file "settings.json landed" "$P/.claude/settings.json"
assert_ok "writes .mcp.json on request" sh "$INIT" "$P" --mcp
assert_file ".mcp.json landed" "$P/.mcp.json"
if command -v jq >/dev/null 2>&1; then
    assert_ok "settings.json is valid JSON" jq empty "$P/.claude/settings.json"
    assert_ok ".mcp.json is valid JSON"     jq empty "$P/.mcp.json"
fi

# --- a project that already configures OpenCode -----------------------------

# The user's own config is not edited around. Reporting the missing glob is the
# whole behaviour here, because a silent merge would rewrite a file they own.
Q="$SB/existing"; mkdir -p "$Q"
printf '{"model":"anthropic/some-model"}\n' > "$Q/opencode.json"
out=$(sh "$INIT" "$Q" 2>&1)
assert_eq "an existing opencode.json is left alone" '{"model":"anthropic/some-model"}' "$(cat "$Q/opencode.json")"
assert_eq "the missing instructions glob is reported" "1" \
    "$(printf '%s' "$out" | grep -c 'does not list ".claude/rules/\*.md"')"
assert_eq "the rest of the scaffold still happened" "1" \
    "$([ -d "$Q/.claude/skills" ] && echo 1 || echo 0)"

# A config that already has the glob must not be nagged about it.
R="$SB/already"; mkdir -p "$R"
printf '{"instructions":[".claude/rules/*.md"]}\n' > "$R/opencode.json"
out=$(sh "$INIT" "$R" 2>&1)
assert_eq "a config that already points at the rules is quiet" "0" \
    "$(printf '%s' "$out" | grep -c 'does not list')"

# An opencode.jsonc counts as the project's config too; writing a second file in
# the other extension would give OpenCode two configs to merge.
T="$SB/jsonc"; mkdir -p "$T"
printf '{"instructions":[".claude/rules/*.md"]}\n' > "$T/opencode.jsonc"
sh "$INIT" "$T" >/dev/null 2>&1
assert_eq "opencode.jsonc is recognised as the config" "0" \
    "$([ -e "$T/opencode.json" ] && echo 1 || echo 0)"

# --- a directory outside Git ------------------------------------------------

U="$SB/nogit"; mkdir -p "$U"
out=$(sh "$INIT" "$U" 2>&1)
assert_eq "warns when there is no worktree boundary" "1" \
    "$(printf '%s' "$out" | grep -c 'not a Git repository')"
assert_eq "and scaffolds anyway" "1" "$([ -f "$U/CLAUDE.md" ] && echo 1 || echo 0)"

# --- the standing rule ------------------------------------------------------

src=$(cat "$INIT")
assert_eq "init-project.sh never stages"  "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*add')"
assert_eq "init-project.sh never commits" "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*commit')"
assert_eq "init-project.sh never pushes"  "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*push')"
out=$(sh "$INIT" "$P" 2>&1)
assert_eq "an already-scaffolded project offers no commit command" "0" \
    "$(printf '%s' "$out" | grep -c 'git -C')"

sandbox_rm "$SB"
printf '\n%s assertions, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
