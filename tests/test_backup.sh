#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/backup.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
TS=$(ad_timestamp)

mkdir -p "$HOME/.claude"
printf 'original\n' > "$HOME/.claude/CLAUDE.md"

slot=$(ad_backup_move "$TS" "$HOME/.claude/CLAUDE.md")
assert_file "backup slot exists" "$slot"
assert_eq "backup preserves content" "original" "$(cat "$slot")"
assert_fail "original is gone after the move" test -e "$HOME/.claude/CLAUDE.md"
case "$slot" in
    "$SB/home/.local/state/agent-dotfiles/backups/$TS"/*) _r=ok ;;
    *) _r="$slot" ;;
esac
assert_eq "backup lives under state home, not under .claude" "ok" "$_r"

ad_backup_restore "$slot" "$HOME/.claude/CLAUDE.md"
assert_eq "restore returns the original content" "original" "$(cat "$HOME/.claude/CLAUDE.md")"
assert_fail "restore refuses to clobber an existing target" \
    ad_backup_restore "$slot" "$HOME/.claude/CLAUDE.md"

assert_eq "latest backup is the timestamp we used" "$TS" "$(ad_backup_latest)"

sandbox_rm "$SB"
