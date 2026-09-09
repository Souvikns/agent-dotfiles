#!/bin/sh
# validate.sh — check the repository without touching the home directory.
set -u

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/settings.sh"

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

tmp=$(mktemp "${TMPDIR:-/tmp}/agent-dotfiles-val.XXXXXX")
trap 'rm -f "$tmp"' EXIT INT TERM

# --- dependencies -----------------------------------------------------------
if command -v jq >/dev/null 2>&1; then ok "jq present"
else bad "jq missing (brew install jq / apt install jq)"; fi

# --- JSON parses ------------------------------------------------------------
# opencode.jsonc must be strict JSON. OpenCode permits comments there, but this
# repository does not use them, so validation needs no JSONC parser — and a
# naive // stripper would corrupt "https://opencode.ai/config.json".
for f in "$AD_ROOT/claude/settings.json" \
         "$AD_ROOT/claude/keybindings.json" \
         "$AD_ROOT/opencode/opencode.jsonc" \
         "$AD_ROOT"/claude/machines/*.json \
         "$AD_ROOT"/opencode/machines/*.json; do
    [ -f "$f" ] || continue
    if jq empty "$f" >/dev/null 2>&1; then ok "parses: ${f#"$AD_ROOT"/}"
    else bad "invalid JSON: ${f#"$AD_ROOT"/}"; fi
done

# --- every machine's merge, not just this one -------------------------------
# A machine file broken on the MacBook must fail there, or the breakage only
# surfaces after it has been pulled onto the ThinkPad.
for f in "$AD_ROOT"/claude/machines/*.json; do
    [ -f "$f" ] || continue
    m=$(basename "$f" .json)
    if ad_settings_merge /dev/null "$AD_ROOT/claude/settings.json" "$f" >/dev/null 2>&1
    then ok "settings merge for machine: $m"
    else bad "settings merge fails for machine: $m"; fi
done

# --- markdown frontmatter ---------------------------------------------------
find "$AD_ROOT/claude" "$AD_ROOT/opencode" "$AD_ROOT/shared" \
     -name '*.md' -type f > "$tmp" 2>/dev/null || true
while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(head -1 "$f")" = "---" ] || continue
    if sed -n '2,$p' "$f" | grep -q '^---$'; then
        ok "frontmatter closed: ${f#"$AD_ROOT"/}"
    else
        bad "unterminated frontmatter: ${f#"$AD_ROOT"/}"
    fi
done < "$tmp"

# --- referenced paths resolve ----------------------------------------------
if [ -f "$AD_ROOT/claude/statusline.sh" ]; then
    if [ -x "$AD_ROOT/claude/statusline.sh" ]; then ok "statusline.sh is executable"
    else bad "statusline.sh is not executable (chmod +x)"; fi
fi
if jq -e '.instructions' "$AD_ROOT/opencode/opencode.jsonc" >/dev/null 2>&1; then
    ok "opencode declares instructions"
else
    bad "opencode.jsonc has no instructions key; shared/ would not be loaded"
fi

# --- shell syntax -----------------------------------------------------------
for f in "$AD_ROOT"/scripts/*.sh "$AD_ROOT"/scripts/lib/*.sh "$AD_ROOT"/tests/*.sh; do
    [ -f "$f" ] || continue
    if sh -n "$f" 2>/dev/null; then ok "syntax: ${f#"$AD_ROOT"/}"
    else bad "syntax error: ${f#"$AD_ROOT"/}"; fi
done
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s sh "$AD_ROOT"/scripts/*.sh "$AD_ROOT"/scripts/lib/*.sh >/dev/null 2>&1
    then ok "shellcheck clean"
    else bad "shellcheck reported problems (run: shellcheck -s sh scripts/*.sh scripts/lib/*.sh)"; fi
else
    printf '  warn shellcheck not installed; CI will run it\n'
fi

# --- no private paths or secrets in installed content -----------------------
# Only content that actually gets installed is scanned. docs/ and tests/ are
# excluded by design: the spec, the plan, and the settings tests all legitimately
# quote a private path as example data.
find "$AD_ROOT/shared" "$AD_ROOT/opencode" "$AD_ROOT/claude" "$AD_ROOT/scripts" \
     -type f > "$tmp" 2>/dev/null || true
if [ -f "$AD_ROOT/README.md" ]; then printf '%s\n' "$AD_ROOT/README.md" >> "$tmp"; fi
hits=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -qE '(/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+)' "$f" 2>/dev/null; then
        bad "absolute home path in ${f#"$AD_ROOT"/}"; hits=1
    fi
    if grep -qE '(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|BEGIN [A-Z ]*PRIVATE KEY)' "$f" 2>/dev/null; then
        bad "possible secret in ${f#"$AD_ROOT"/}"; hits=1
    fi
done < "$tmp"
if [ "$hits" -eq 0 ]; then ok "no private paths or secret patterns in installed content"; fi

printf '\n%s check(s) failed\n' "$fails"
[ "$fails" -eq 0 ]
