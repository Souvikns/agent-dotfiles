#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/manifest.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

ad_manifest_init "$SB/repo" macbook
assert_file "manifest created" "$(ad_manifest_path)"
assert_eq "machine recorded" "macbook" "$(ad_manifest_machine)"
assert_eq "revision of a non-repo is unknown" "unknown" \
    "$(jq -r .revision "$(ad_manifest_path)")"
assert_eq "targets start empty" "0" \
    "$(jq '.targets | length' "$(ad_manifest_path)")"

ad_manifest_add dir "$SB/repo/claude/skills" "$HOME/.claude/skills" ""
assert_eq "one target recorded" "1" "$(jq '.targets|length' "$(ad_manifest_path)")"
assert_eq "null backup when none taken" "null" \
    "$(jq -r '.targets[0].backup' "$(ad_manifest_path)")"

ad_manifest_add dir "$SB/repo/claude/skills" "$HOME/.claude/skills" "/some/slot"
assert_eq "re-adding the same target replaces rather than duplicates" "1" \
    "$(jq '.targets|length' "$(ad_manifest_path)")"
assert_eq "backup slot updated on replace" "/some/slot" \
    "$(jq -r '.targets[0].backup' "$(ad_manifest_path)")"

ad_manifest_add file "$SB/repo/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" ""
assert_eq "second distinct target appended" "2" "$(jq '.targets|length' "$(ad_manifest_path)")"
assert_eq "targets render as pipe rows" \
    "file|$SB/repo/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md|" \
    "$(ad_manifest_targets | grep 'CLAUDE.md')"

sandbox_rm "$SB"
