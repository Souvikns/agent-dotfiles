#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
INSTALL="$REPO/scripts/install.sh"
UNINSTALL="$REPO/scripts/uninstall.sh"

assert_ok   "--help works" sh "$UNINSTALL" --help
assert_fail "uninstall without a manifest fails cleanly" sh "$UNINSTALL"

sh "$INSTALL" --all --machine macbook >/dev/null

sh "$UNINSTALL" --dry-run >/dev/null
assert_link "dry run left the link" "$HOME/.claude/skills" "$REPO/skills"

rm "$HOME/.claude/agents"; ln -s "$SB/elsewhere" "$HOME/.claude/agents"
rc=0; sh "$UNINSTALL" >/dev/null 2>&1 || rc=$?
assert_eq   "drift causes exit 3" "3" "$rc"
assert_link "drifted target left alone" "$HOME/.claude/agents" "$SB/elsewhere"
assert_fail "matching targets still removed alongside the refusal" \
    test -L "$HOME/.claude/skills"
assert_file "generated settings not removed by default" "$HOME/.claude/settings.json"

sh "$UNINSTALL" --force >/dev/null
assert_fail "force removed the drifted target" test -e "$HOME/.claude/agents"
assert_fail "force removed the generated settings" test -e "$HOME/.claude/settings.json"

sandbox_rm "$SB"; SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
mkdir -p "$HOME/.claude/skills/mine"; printf 'original\n' > "$HOME/.claude/skills/mine/SKILL.md"
sh "$INSTALL" --claude --machine macbook --force >/dev/null
sh "$UNINSTALL" --restore >/dev/null
assert_file "restore returned the displaced content" "$HOME/.claude/skills/mine/SKILL.md"
assert_eq   "restored content is intact" "original" "$(cat "$HOME/.claude/skills/mine/SKILL.md")"
assert_fail "restored path is no longer our link" test -L "$HOME/.claude/skills"

sandbox_rm "$SB"
