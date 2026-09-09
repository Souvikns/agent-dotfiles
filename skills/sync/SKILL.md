---
name: sync
description: Sync this machine's agent configuration with the agent-dotfiles repository. Reports what changed locally, then fast-forwards and reinstalls. Never commits — that is the user's to do. Use when the user says sync my config, or asks to pick up config changes from another machine.
---

# Sync agent configuration

Deliberately no `!`-injected shell here. Injected commands abort unless
pre-approved, which would need a broad `Bash(sh:*)` grant, and this repository's
security posture is to avoid broad allow rules for convenience. Run the script
as a normal tool call instead.

## The one rule

**You do not commit.** Not with permission, not after asking, not "just this
once". `sync.sh` has no staging, commit, or push code in it — that is deliberate,
and you must not reach around it with your own `git` calls either. Your job ends
at telling the user what changed and handing them the command.

## 1. Run it

The repository path is recorded in the install manifest, so this works no matter
where it was cloned:

```sh
sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/sync.sh"
```

With no subcommand this prints the status, then fast-forwards and reinstalls.
Use `sync.sh status` instead when the user only wants to know where things stand.

If the manifest is missing, the config was never installed on this machine —
say so and stop. Do not guess a path.

## 2. Report

Two things the user cares about, in this order:

- **What is uncommitted here.** Describe the changes in plain language — what was
  added, what was edited — and repeat the `git` command the script printed. If
  they ask you to commit, decline and point at the command; they hold that step
  on purpose.
- **What became live.** Name the skills, agents, commands, or settings that
  changed, rather than restating that the command ran.

## Situations to report rather than work around

- **No remote configured.** There is nothing to pull. Say so, and offer to add
  one — but adding it is a git write, so only do that if they ask directly.
- **Pull refused because the branch diverged.** The script stops and will not
  merge or rebase. Show the user and let them reconcile it. Do not offer to run
  the merge yourself.
- **Install refused a target** (exit 3). Something at that path is not ours and
  was not overwritten. Report which target and why; suggest `--force` only if
  the user confirms the existing file is disposable — it is backed up either way.
