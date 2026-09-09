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
"$HOME/.agent-dotfiles/scripts/install.sh" --all --machine macos >/dev/null 2>&1

assert_ok   "--help works" sh "$SYNC" --help
assert_fail "unknown subcommand fails" sh "$SYNC" bogus

# The whole point of the rewrite: this script must not be able to write history.
# The pattern anchors on a line that *invokes* git, so the commit command the
# script prints for the user does not count against it.
src=$(cat "$SYNC")
assert_eq "sync.sh never stages"  "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*add')"
assert_eq "sync.sh never commits" "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*commit')"
assert_eq "sync.sh never pushes"  "0" "$(printf '%s' "$src" | grep -cE '^[[:space:]]*git .*push')"
assert_fail "the push subcommand is gone" sh "$SYNC" push "a message"

out=$(sh "$SYNC" status 2>&1)
assert_eq "status reports the machine" "1" "$(printf '%s' "$out" | grep -c 'machine: *macos')"
assert_eq "status reports a clean tree" "1" "$(printf '%s' "$out" | grep -c 'no local changes')"
assert_eq "status names the missing remote" "1" "$(printf '%s' "$out" | grep -c 'no remote configured')"
assert_eq "a clean tree offers no commit command" "0" "$(printf '%s' "$out" | grep -c 'git -C')"

printf 'x\n' > "$HOME/.agent-dotfiles/shared/note.md"
out=$(sh "$SYNC" status 2>&1)
assert_eq "status lists an untracked file" "1" "$(printf '%s' "$out" | grep -c 'shared/note.md')"
assert_eq "status hands back the commit command" "1" "$(printf '%s' "$out" | grep -c 'git -C .* commit')"
assert_eq "status changes nothing" "1" \
    "$(cd "$HOME/.agent-dotfiles" && git status --porcelain | grep -c 'shared/note.md')"
assert_eq "status stages nothing" "0" \
    "$(cd "$HOME/.agent-dotfiles" && git diff --cached --name-only | wc -l | tr -d ' ')"

# pull with no remote must still reinstall rather than erroring out
out=$(sh "$SYNC" pull 2>&1); rc=$?
assert_eq "pull succeeds without a remote" "0" "$rc"
assert_eq "pull says it skipped the fetch" "1" "$(printf '%s' "$out" | grep -c 'no remote configured')"
# install.sh derives its root with `pwd -P`, so on macOS the link target is the
# resolved /private/var form. Compare against the resolved path, not $HOME's.
CLONE=$(CDPATH= cd -- "$HOME/.agent-dotfiles" && pwd -P)
assert_link "pull left the install intact" "$HOME/.claude/skills" "$CLONE/skills"

# No subcommand is the everyday path: report, then pull and reinstall.
out=$(sh "$SYNC" 2>&1); rc=$?
assert_eq "bare sync succeeds" "0" "$rc"
# install.sh names the machine too, so count the line rather than assert one:
# what matters is that the status block comes first, before anything is touched.
assert_eq "bare sync leads with status" "1" \
    "$(printf '%s\n' "$out" | head -1 | grep -c '^repo: ')"
assert_eq "bare sync reinstalls" "1" "$(printf '%s' "$out" | grep -c 'reinstalling from the local checkout')"
assert_eq "bare sync still commits nothing" "1" \
    "$(cd "$HOME/.agent-dotfiles" && git status --porcelain | grep -c 'shared/note.md')"

# a new skill in the repo is live with no install step at all
mkdir -p "$HOME/.agent-dotfiles/skills/fresh"
printf -- '---\nname: fresh\ndescription: x\n---\nx\n' > "$HOME/.agent-dotfiles/skills/fresh/SKILL.md"
assert_file "new skill is already live" "$HOME/.claude/skills/fresh/SKILL.md"

sandbox_rm "$SB"
