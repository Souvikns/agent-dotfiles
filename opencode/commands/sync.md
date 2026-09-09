---
description: Sync this machine's agent configuration with the agent-dotfiles repository
---

Sync the agent configuration for this machine. Same script both tools use.

## The one rule

**Do not commit.** `sync.sh` deliberately contains no staging, commit, or push
code, and you must not reach around it with your own `git` calls. Report what
changed and hand the user the command; the commit is theirs.

## 1. Run it

The repository path is recorded in the install manifest, so this works no matter
where it was cloned:

!`sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/sync.sh"`

If that failed, the config was never installed on this machine. Say so and stop
rather than guessing a path.

## 2. Report

- **Uncommitted work here**: describe it in plain language and repeat the `git`
  command the script printed. If asked to commit, decline and point at it.
- **What became live**: name the skills, agents, commands, or settings that
  changed — not just that the command ran.

## Report, do not work around

- **No remote configured**: nothing to pull. Offer to add one, but only add it if
  asked directly — that is a git write.
- **Pull refused, branch diverged**: the script will not merge or rebase, and
  neither should you. Let the user reconcile.
- **Install refused a target** (exit 3): something there is not ours and was not
  overwritten. Say which, and why.
