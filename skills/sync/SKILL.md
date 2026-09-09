---
name: sync
description: Sync this machine's agent configuration with the agent-dotfiles repository. Reviews local changes, asks before committing and pushing them, then pulls and reinstalls. Use when the user says sync my config, push my dotfiles, or asks to pick up config changes from another machine.
---

# Sync agent configuration

Deliberately no `!`-injected shell here. Injected commands abort unless
pre-approved, which would need a broad `Bash(sh:*)` grant, and this repository's
security posture is to avoid broad allow rules for convenience. Run the script
as a normal tool call instead.

## 1. Find the repository and read the current state

The repository path is recorded in the install manifest, so this works no matter
where it was cloned:

```sh
sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/sync.sh" status
```

If the manifest is missing, the config was never installed on this machine —
say so and stop. Do not guess a path.

`status` is read-only. It reports the repo path, machine name, branch, remote
state, and any uncommitted changes.

## 2. If there are local changes, show them and ask

List the changed files for the user in plain language — what was added, what was
modified — and ask whether to commit and push. **Wait for an answer.** Do not
commit on their behalf without one; the confirmation is the entire reason this
is a command rather than a shell alias.

If they agree, write a specific commit message describing what actually changed
("add deploy-notes skill", not "update config") and run:

```sh
sh <repo>/scripts/sync.sh push "<message>"
```

If the commit fails because the repository signs commits, the GPG passphrase
prompt cannot appear here. Tell the user to run the commit themselves in a
terminal, and carry on to step 3.

## 3. Pull and reinstall

```sh
sh <repo>/scripts/sync.sh pull
```

This runs `git pull --ff-only` and then `install.sh --all`.

## 4. Report what changed

Say what actually became live — new skills, agents, commands, or settings —
rather than restating that the command ran.

## Situations to report rather than work around

- **No remote configured.** `status` says so. Commits stay local; there is
  nothing to pull. Tell the user, and offer to add a remote.
- **Pull refused because the branch diverged.** The script stops and will not
  merge or rebase. Show the user and let them reconcile it.
- **Install refused a target** (exit 3). Something at that path is not ours and
  was not overwritten. Report which target and why; suggest `--force` only if
  the user confirms the existing file is disposable — it is backed up either way.
