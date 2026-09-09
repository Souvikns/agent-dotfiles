#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
V="$REPO/scripts/validate.sh"

assert_ok "the repository validates as shipped" sh "$V"

SB=$(sandbox_new)
cp -R "$REPO" "$SB/clone"
rm -rf "$SB/clone/.git"

printf '{"model": }\n' > "$SB/clone/claude/settings.json"
assert_fail "malformed settings.json fails validation" sh "$SB/clone/scripts/validate.sh"
printf '{}\n' > "$SB/clone/claude/settings.json"

# A machine file broken here must fail here, not after it reaches that machine.
printf '{"model": }\n' > "$SB/clone/claude/machines/thinkpad.json"
assert_fail "a malformed machine file fails even when it is not this machine" \
    sh "$SB/clone/scripts/validate.sh"
printf '{}\n' > "$SB/clone/claude/machines/thinkpad.json"

printf -- '---\nname: broken\n' > "$SB/clone/skills/broken.md"
assert_fail "unterminated frontmatter fails validation" sh "$SB/clone/scripts/validate.sh"
rm "$SB/clone/skills/broken.md"

printf 'export TOKEN=/Users/someone/secret\n' > "$SB/clone/shared/leak.md"
assert_fail "an absolute home path in installed content fails validation" \
    sh "$SB/clone/scripts/validate.sh"
rm "$SB/clone/shared/leak.md"

assert_ok "clone validates again once the faults are removed" sh "$SB/clone/scripts/validate.sh"

sandbox_rm "$SB"
