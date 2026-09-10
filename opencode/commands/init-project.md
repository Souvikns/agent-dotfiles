---
description: Scaffold the project-level configuration that Claude Code and OpenCode both read
---

Set up `.claude` and `.opencode` configuration for this project. Same script both
tools use; it writes only what is missing.

## 1. Run it

The repository path is recorded in the install manifest, so this works wherever
the clone lives:

!`sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/init-project.sh" $ARGUMENTS`

Arguments are passed straight through: a path to scaffold somewhere other than
here, `--dry-run` to see the plan, `--settings` and `--mcp` for the two files left
out of the default.

If that failed, the configuration was never installed on this machine. Say so and
stop rather than guessing a path.

## 2. Tell the user what is shared

Three of the six surfaces are read by both tools; the rest are not, and a file in
the wrong place is loaded by nobody and warns about nothing.

- **Written once, both tools read it**: `CLAUDE.md`, `.claude/rules/*.md`,
  `.claude/skills/<name>/SKILL.md`.
- **Claude Code only**: `.claude/agents/`, `.claude/commands/`,
  `.claude/settings.json`, `.mcp.json`.
- **OpenCode only**: `.opencode/agent/`, `.opencode/command/`, `opencode.json`.

An agent must be written twice and the copies are not interchangeable: OpenCode
refuses to start when an agent file uses Claude Code's `tools: Read, Grep` string
form, because it expects an object.

## 3. Do not commit

The script stages nothing and prints the `git` command. Report what changed and
hand that over; the commit is the user's.

## Report, do not work around

- **An `opencode.json` was already there**: it is not edited. The script prints
  the missing `instructions` entry — pass it on instead of applying it yourself,
  unless asked.
- **Not a Git repository**: the script warns and continues. OpenCode stops
  looking for project files at the worktree root, so this directory becomes its
  own boundary.
