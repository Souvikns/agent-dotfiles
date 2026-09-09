#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/targets.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

rows=$(ad_targets_claude)
assert_eq "claude table has 11 rows" "11" "$(printf '%s\n' "$rows" | grep -c .)"
assert_eq "shared is linked as claude rules" \
    "dir|shared|$SB/home/.claude/rules" \
    "$(printf '%s\n' "$rows" | grep '/rules$')"
assert_eq "skills is one source shared by both tools" "skills" \
    "$(ad_row_source "$(printf '%s\n' "$rows" | grep '/skills$')")"
assert_eq "settings is generated, not linked" \
    "gen" \
    "$(ad_row_kind "$(printf '%s\n' "$rows" | grep '/settings.json$')")"
assert_eq "plugins is never a claude target" "0" \
    "$(printf '%s\n' "$rows" | grep -c '/.claude/plugins$')"
assert_eq "projects is never a claude target" "0" \
    "$(printf '%s\n' "$rows" | grep -c '/.claude/projects$')"

orows=$(ad_targets_opencode thinkpad)
assert_eq "opencode table has 8 rows" "8" "$(printf '%s\n' "$orows" | grep -c .)"
assert_eq "machine file is linked to the fixed path" \
    "file|opencode/machines/thinkpad.json|$SB/home/.config/opencode/machine.json" \
    "$(printf '%s\n' "$orows" | grep '/machine.json$')"
assert_eq "node_modules is never an opencode target" "0" \
    "$(printf '%s\n' "$orows" | grep -c 'node_modules')"
assert_eq "opencode skills point at the same shared source" "skills" \
    "$(ad_row_source "$(printf '%s\n' "$orows" | grep '/skills$')")"

row='dir|claude/skills|/tmp/x/skills'
assert_eq "row kind accessor"   "dir"           "$(ad_row_kind   "$row")"
assert_eq "row source accessor" "claude/skills" "$(ad_row_source "$row")"
assert_eq "row target accessor" "/tmp/x/skills" "$(ad_row_target "$row")"

sandbox_rm "$SB"
