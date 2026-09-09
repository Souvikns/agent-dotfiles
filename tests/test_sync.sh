#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
git clone -q "$REPO" "$HOME/.agent-dotfiles"
# Overlay the working tree on top of the clone. Without this the test would
# exercise the last commit rather than the code actually on disk, and a change
# under test would silently not be there.
( cd "$REPO" && tar cf - --exclude .git . ) | ( cd "$HOME/.agent-dotfiles" && tar xf - )
# Settle the overlay into a commit so the tree starts clean. HOME is sandboxed,
# so there is no global git identity to inherit and it must be supplied here.
git -C "$HOME/.agent-dotfiles" add -A
git -C "$HOME/.agent-dotfiles" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    commit -qm "overlay working tree" 2>/dev/null || true
# Drop the origin the clone inherited, so the no-remote path is what gets tested.
git -C "$HOME/.agent-dotfiles" remote remove origin 2>/dev/null || true
SYNC="$HOME/.agent-dotfiles/scripts/sync.sh"
"$HOME/.agent-dotfiles/scripts/install.sh" --all --machine macbook >/dev/null 2>&1

assert_ok   "--help works" sh "$SYNC" --help
assert_fail "unknown subcommand fails" sh "$SYNC" bogus
assert_fail "push without a message fails" sh "$SYNC" push

out=$(sh "$SYNC" status 2>&1)
assert_eq "status reports the machine" "1" "$(printf '%s' "$out" | grep -c 'machine: *macbook')"
assert_eq "status reports a clean tree" "1" "$(printf '%s' "$out" | grep -c 'no local changes')"
assert_eq "status names the missing remote" "1" "$(printf '%s' "$out" | grep -c 'no remote configured')"

printf 'x\n' > "$HOME/.agent-dotfiles/shared/note.md"
out=$(sh "$SYNC" status 2>&1)
assert_eq "status lists an untracked file" "1" "$(printf '%s' "$out" | grep -c 'shared/note.md')"
assert_eq "status changes nothing" "1" \
    "$(cd "$HOME/.agent-dotfiles" && git status --porcelain | grep -c 'shared/note.md')"

# pull with no remote must still reinstall rather than erroring out
out=$(sh "$SYNC" pull 2>&1); rc=$?
assert_eq "pull succeeds without a remote" "0" "$rc"
assert_eq "pull says it skipped the fetch" "1" "$(printf '%s' "$out" | grep -c 'no remote configured')"
# install.sh derives its root with `pwd -P`, so on macOS the link target is the
# resolved /private/var form. Compare against the resolved path, not $HOME's.
CLONE=$(CDPATH= cd -- "$HOME/.agent-dotfiles" && pwd -P)
assert_link "pull left the install intact" "$HOME/.claude/skills" "$CLONE/skills"

# a new skill in the repo is live with no install step at all
mkdir -p "$HOME/.agent-dotfiles/skills/fresh"
printf -- '---\nname: fresh\ndescription: x\n---\nx\n' > "$HOME/.agent-dotfiles/skills/fresh/SKILL.md"
assert_file "new skill is already live" "$HOME/.claude/skills/fresh/SKILL.md"

sandbox_rm "$SB"
