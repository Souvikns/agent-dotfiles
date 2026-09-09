#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/backup.sh
. ../scripts/lib/link.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
TS=$(ad_timestamp)
SRC="$SB/repo/claude/skills"
TGT="$HOME/.claude/skills"
mkdir -p "$SRC" "$HOME/.claude"

assert_eq "missing target" "missing" "$(ad_link_state "$TGT" "$SRC")"

out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS")
assert_eq "creates the link" "create" "$out"
assert_link "link points at the repo" "$TGT" "$SRC"
assert_eq "correct link reads as ok" "ok" "$(ad_link_state "$TGT" "$SRC")"

out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS")
assert_eq "rerun is a no-op" "noop" "$out"
assert_eq "no backup was created on a no-op run" "0" \
    "$(ls -1 "$(ad_state_home)/backups" 2>/dev/null | wc -l | tr -d ' ')"

rm "$TGT"; ln -s "$SB/elsewhere" "$TGT"
assert_eq "foreign link detected" "foreign" "$(ad_link_state "$TGT" "$SRC")"
rc=0; out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS") || rc=$?
assert_eq "foreign link refused" "3" "$rc"
assert_eq "refusal names the reason" "refuse foreign" "$out"
assert_link "refusal left the foreign link intact" "$TGT" "$SB/elsewhere"

rm "$TGT"; mkdir -p "$TGT/impeccable"; printf 'x\n' > "$TGT/impeccable/SKILL.md"
assert_eq "real directory detected" "occupied" "$(ad_link_state "$TGT" "$SRC")"
rc=0; out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS") || rc=$?
assert_eq "real directory refused without --force" "3" "$rc"
assert_file "refusal left the real content intact" "$TGT/impeccable/SKILL.md"

out=$(ad_link_apply "$SRC" "$TGT" 1 0 "$TS")
assert_link "force replaced with our link" "$TGT" "$SRC"
slot=$(printf '%s' "$out" | cut -d' ' -f2)
assert_file "displaced content preserved in the backup" "$slot/impeccable/SKILL.md"

rm "$TGT"
out=$(ad_link_apply "$SRC" "$TGT" 0 1 "$TS")
assert_eq "dry run reports the create" "create" "$out"
assert_fail "dry run did not create the link" test -e "$TGT"

rc=0; out=$(ad_link_apply "$SB/nope" "$HOME/.claude/nope" 0 0 "$TS") || rc=$?
assert_eq "missing source exits 4" "4" "$rc"
assert_eq "missing source reports itself" "missing-source" "$out"

sandbox_rm "$SB"
