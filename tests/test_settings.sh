#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/settings.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
mkdir -p "$SB/repo/claude/machines" "$HOME/.claude"
LIVE="$HOME/.claude/settings.json"
BASE="$SB/repo/claude/settings.json"
MACH="$SB/repo/claude/machines/macbook.json"

# The live file carries what Claude Code wrote for itself, including the
# private auto-mode block that must never enter the repository.
cat > "$LIVE" <<'J'
{"theme":"dark","autoMode":{"environment":["/Users/souvik/private/repo"]},
 "permissions":{"allow":["Bash(ls:*)"]}}
J
cat > "$BASE" <<'J'
{"model":"opus","permissions":{"allow":["Bash(git:*)"],"deny":["Bash(rm:*)"]}}
J
printf '{"model":"sonnet"}\n' > "$MACH"

out=$(ad_settings_merge "$LIVE" "$BASE" "$MACH")

assert_eq "machine layer beats base" "sonnet" "$(printf '%s' "$out" | jq -r .model)"
assert_eq "live-only key survives regeneration" "dark" "$(printf '%s' "$out" | jq -r .theme)"
assert_eq "private auto-mode block survives and is untouched" \
    "/Users/souvik/private/repo" \
    "$(printf '%s' "$out" | jq -r '.autoMode.environment[0]')"
assert_eq "objects merge recursively: base deny is added" "Bash(rm:*)" \
    "$(printf '%s' "$out" | jq -r '.permissions.deny[0]')"
assert_eq "arrays replace rather than concatenate" "Bash(git:*)" \
    "$(printf '%s' "$out" | jq -r '.permissions.allow[0]')"
assert_eq "arrays replace: length is base's, not the sum" "1" \
    "$(printf '%s' "$out" | jq '.permissions.allow | length')"

out2=$(ad_settings_merge /nonexistent "$BASE" /nonexistent)
assert_eq "absent live and machine layers are tolerated" "opus" \
    "$(printf '%s' "$out2" | jq -r .model)"

ad_settings_write "$SB/repo" macbook "$LIVE" 1 0
assert_eq "clean regeneration drops live-only keys" "null" "$(jq -r '.theme' "$LIVE")"
assert_eq "clean regeneration keeps repository keys" "sonnet" "$(jq -r .model "$LIVE")"

printf '{"marker":"untouched"}\n' > "$LIVE"
ad_settings_write "$SB/repo" macbook "$LIVE" 0 1
assert_eq "dry run leaves the file untouched" "untouched" "$(jq -r .marker "$LIVE")"

sandbox_rm "$SB"
