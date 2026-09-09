---
description: Sync this machine's agent configuration with the agent-dotfiles repository
---

Sync the agent configuration for this machine. Same script both tools use.

## 1. Read the current state

The repository path is recorded in the install manifest, so this works no matter
where it was cloned:

!`sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/sync.sh" status`

If that failed, the config was never installed on this machine. Say so and stop
rather than guessing a path.

## 2. If there are local changes, show them and ask

List what changed in plain language and ask whether to commit and push. **Wait
for an answer** — do not commit unprompted. Then, with a message describing what
actually changed:

```sh
sh <repo>/scripts/sync.sh push "<message>"
```

## 3. Pull and reinstall

```sh
sh <repo>/scripts/sync.sh pull
```

## 4. Report what became live

Name the skills, agents, commands, or settings that changed — not just that the
command ran.

## Report, do not work around

- **No remote configured**: commits stay local, nothing to pull. Offer to add one.
- **Pull refused, branch diverged**: the script will not merge or rebase. Let the
  user reconcile.
- **Install refused a target** (exit 3): something there is not ours and was not
  overwritten. Say which, and why.
