#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
INSTALL="$REPO/scripts/install.sh"

assert_ok   "--help works and exits 0" sh "$INSTALL" --help
assert_fail "no component flag is a usage error" sh "$INSTALL" --machine macbook
assert_fail "no machine on first run is an error" sh "$INSTALL" --all

sh "$INSTALL" --all --machine macbook --dry-run >/dev/null
assert_fail "dry run created no claude dir" test -e "$HOME/.claude/skills"
assert_fail "dry run wrote no manifest" test -e "$(ad_state_home)/manifest.json"
assert_fail "dry run recorded no machine name" test -e "$(ad_config_home)/machine"

sh "$INSTALL" --all --machine macbook >/dev/null
assert_link "skills linked into claude" "$HOME/.claude/skills" "$REPO/skills"
assert_link "same skills source linked into opencode" \
    "$HOME/.config/opencode/skills" "$REPO/skills"
assert_link "rules linked to shared" "$HOME/.claude/rules" "$REPO/shared"
assert_link "opencode machine.json linked" \
    "$HOME/.config/opencode/machine.json" "$REPO/opencode/machines/macbook.json"
assert_file "settings generated" "$HOME/.claude/settings.json"
assert_fail "settings is a real file, not a link" test -L "$HOME/.claude/settings.json"
assert_fail "plugins never linked" test -L "$HOME/.claude/plugins"
assert_file "manifest written" "$(ad_state_home)/manifest.json"
assert_eq   "machine recorded" "macbook" "$(cat "$(ad_config_home)/machine")"

before=$(ls -1 "$(ad_state_home)/backups" 2>/dev/null | wc -l | tr -d ' ')
sh "$INSTALL" --all >/dev/null
after=$(ls -1 "$(ad_state_home)/backups" 2>/dev/null | wc -l | tr -d ' ')
assert_eq   "rerun creates no new backup" "$before" "$after"
assert_eq   "rerun needs no --machine" "macbook" "$(cat "$(ad_config_home)/machine")"
assert_link "rerun left the link alone" "$HOME/.claude/skills" "$REPO/skills"

rm "$HOME/.claude/skills"; mkdir -p "$HOME/.claude/skills/mine"
rc=0; sh "$INSTALL" --claude >/dev/null 2>&1 || rc=$?
assert_eq   "conflict exits 3" "3" "$rc"
assert_file "conflicting content untouched" "$HOME/.claude/skills/mine"

sh "$INSTALL" --claude --force >/dev/null
assert_link "force replaced the conflict" "$HOME/.claude/skills" "$REPO/skills"
assert_eq   "exactly one backup generation exists" "1" \
    "$(ls -1 "$(ad_state_home)/backups" | wc -l | tr -d ' ')"

sandbox_rm "$SB"; SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
sh "$INSTALL" --claude --machine thinkpad >/dev/null
assert_file "claude-only install touched claude" "$HOME/.claude/skills"
assert_fail "claude-only install did not touch opencode" test -e "$HOME/.config/opencode/agents"

sandbox_rm "$SB"
