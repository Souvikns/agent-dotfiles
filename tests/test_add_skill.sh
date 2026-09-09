#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

# The dotfiles checkout under test.
cp -R "$REPO" "$HOME/.agent-dotfiles"
rm -rf "$HOME/.agent-dotfiles/.git"
git -C "$HOME/.agent-dotfiles" init -q
git -C "$HOME/.agent-dotfiles" add -A
git -C "$HOME/.agent-dotfiles" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    commit -qm init 2>/dev/null || true
ADD="$HOME/.agent-dotfiles/scripts/add-skill.sh"
"$HOME/.agent-dotfiles/scripts/install.sh" --all --machine macos >/dev/null 2>&1

# An upstream skill package, cloned over the filesystem so the test needs no
# network. add-skill.sh must accept a path as readily as an owner/repo.
UP="$SB/upstream"
mkdir -p "$UP/skills/demo" "$UP/skills/other"
printf -- '---\nname: demo\ndescription: a demo skill\n---\nv1 body\n' > "$UP/skills/demo/SKILL.md"
printf 'reference\n' > "$UP/skills/demo/NOTES.md"
printf -- '---\nname: other\ndescription: another\n---\nx\n' > "$UP/skills/other/SKILL.md"
git -C "$UP" init -q
git -C "$UP" add -A
git -C "$UP" -c user.name=u -c user.email=u@u -c commit.gpgsign=false commit -qm v1

assert_ok   "--help works" sh "$ADD" --help
assert_fail "no arguments fails" sh "$ADD"
assert_fail "an ambiguous package fails rather than guessing" sh "$ADD" "$UP"
assert_fail "an unknown skill name fails" sh "$ADD" "$UP" --skill nosuch

assert_ok "adds a named skill from a local package" sh "$ADD" "$UP" --skill demo

S="$HOME/.agent-dotfiles/skills/demo"
assert_file "SKILL.md landed in the repository" "$S/SKILL.md"
assert_file "supporting files came along" "$S/NOTES.md"
assert_eq "the skill is a real directory, not a symlink" "0" \
    "$(find "$HOME/.agent-dotfiles/skills" -type l | wc -l | tr -d ' ')"
assert_eq "the upstream .git was not copied" "0" \
    "$([ -e "$S/.git" ] && echo 1 || echo 0)"
assert_eq "only the requested skill was taken" "0" \
    "$([ -e "$HOME/.agent-dotfiles/skills/other" ] && echo 1 || echo 0)"

assert_file "provenance was recorded" "$S/.source"
prov=$(cat "$S/.source")
assert_eq "provenance names the source" "1" "$(printf '%s' "$prov" | grep -c "^source: ")"
assert_eq "provenance pins the commit" "1" "$(printf '%s' "$prov" | grep -c '^commit: [0-9a-f]\{40\}$')"

# The payoff: one copy, visible to both tools, with no install step.
assert_file "live in Claude Code"  "$HOME/.claude/skills/demo/SKILL.md"
assert_file "live in OpenCode"     "$HOME/.config/opencode/skills/demo/SKILL.md"

# Nothing may be staged or committed on the user's behalf.
src=$(cat "$ADD")
assert_eq "add-skill.sh never stages"  "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*add')"
assert_eq "add-skill.sh never commits" "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*commit')"
assert_eq "add-skill.sh never pushes"  "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*push')"
assert_eq "the new skill is left uncommitted" "1" \
    "$(cd "$HOME/.agent-dotfiles" && git status --porcelain | grep -c 'skills/demo')"
assert_eq "nothing was staged" "0" \
    "$(cd "$HOME/.agent-dotfiles" && git diff --cached --name-only | wc -l | tr -d ' ')"

# Re-adding must not silently clobber local edits.
printf 'edited by hand\n' >> "$S/SKILL.md"
assert_fail "re-adding an existing skill is refused" sh "$ADD" "$UP" --skill demo
assert_eq "the refusal left the edit alone" "1" "$(grep -c 'edited by hand' "$S/SKILL.md")"

assert_ok "--force overwrites" sh "$ADD" "$UP" --skill demo --force
assert_eq "the overwrite dropped the edit" "0" "$(grep -c 'edited by hand' "$S/SKILL.md")"
assert_eq "the overwrite was backed up" "1" \
    "$(find "$HOME/.local/state/agent-dotfiles/backups" -name SKILL.md | wc -l | tr -d ' ')"

# Updating follows the recorded source without being told where it is.
printf -- '---\nname: demo\ndescription: a demo skill\n---\nv2 body\n' > "$UP/skills/demo/SKILL.md"
git -C "$UP" add -A
git -C "$UP" -c user.name=u -c user.email=u@u -c commit.gpgsign=false commit -qm v2
assert_ok "--update refetches from the recorded source" sh "$ADD" --update demo
assert_eq "the update brought the new content" "1" "$(grep -c 'v2 body' "$S/SKILL.md")"
assert_fail "--update on an unknown skill fails" sh "$ADD" --update nosuch

out=$(sh "$ADD" --list 2>&1)
assert_eq "--list names the vendored skill" "1" "$(printf '%s' "$out" | grep -c '^demo')"

# A skill authored here, with no .source, is not upstream and must be left alone.
mkdir -p "$HOME/.agent-dotfiles/skills/mine"
printf -- '---\nname: mine\ndescription: x\n---\nx\n' > "$HOME/.agent-dotfiles/skills/mine/SKILL.md"
assert_fail "--update refuses a skill it did not vendor" sh "$ADD" --update mine
out=$(sh "$ADD" --list 2>&1)
assert_eq "--list ignores locally authored skills" "0" "$(printf '%s' "$out" | grep -c '^mine')"

# --all vendors every skill in a package from a single clone. A package with
# fourteen skills should not mean fourteen network fetches.
rm -rf "$HOME/.agent-dotfiles/skills/demo" "$HOME/.agent-dotfiles/skills/other"
assert_fail "--all and --skill together are refused" sh "$ADD" "$UP" --all --skill demo
assert_ok   "--all vendors the whole package" sh "$ADD" "$UP" --all
assert_file "--all took the first skill"  "$HOME/.agent-dotfiles/skills/demo/SKILL.md"
assert_file "--all took the second skill" "$HOME/.agent-dotfiles/skills/other/SKILL.md"
assert_file "--all recorded provenance per skill" "$HOME/.agent-dotfiles/skills/other/.source"
assert_eq "--all copied real files, no symlinks" "0" \
    "$(find "$HOME/.agent-dotfiles/skills" -type l | wc -l | tr -d ' ')"

# A collision must not abort the rest of the batch.
printf 'local edit\n' >> "$HOME/.agent-dotfiles/skills/demo/SKILL.md"
rm -rf "$HOME/.agent-dotfiles/skills/other"
out=$(sh "$ADD" "$UP" --all 2>&1); rc=$?
assert_eq "--all succeeds despite an existing skill" "0" "$rc"
assert_eq "--all names the skill it skipped" "1" \
    "$(printf '%s\n' "$out" | grep -c '^  skipped demo ')"
assert_eq "--all left the local edit alone" "1" \
    "$(grep -c 'local edit' "$HOME/.agent-dotfiles/skills/demo/SKILL.md")"
assert_file "--all still added the missing one" "$HOME/.agent-dotfiles/skills/other/SKILL.md"

assert_ok "--all --force replaces existing skills" sh "$ADD" "$UP" --all --force
assert_eq "--all --force dropped the local edit" "0" \
    "$(grep -c 'local edit' "$HOME/.agent-dotfiles/skills/demo/SKILL.md")"

sandbox_rm "$SB"
