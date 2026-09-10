---
name: init-project
description: Scaffold project-level configuration that Claude Code and OpenCode both read - CLAUDE.md, shared rules, a shared skills directory, and each tool's own agent and command directories. Use when the user wants to set up .claude and .opencode config for a project, or asks where a project rule, skill, agent, or command should live so both tools see it.
---

# Project configuration for both tools

One project, two tools, and only three of the six surfaces are actually shared.
The script writes the layout that both tools read; this skill is about knowing
which file belongs where afterwards.

## 1. Run it

The repository path is recorded in the install manifest, so this works wherever
the clone lives:

```sh
sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/init-project.sh"
```

It scaffolds the current directory. Pass a path to scaffold somewhere else,
`--dry-run` to see the plan first, and `--settings` or `--mcp` for the two files
that are deliberately not part of the default.

Nothing that already exists is touched, so re-running it on a project that has
half the layout is safe and is the intended way to fill in the other half.

## 2. What is shared and what is not

This is the part worth remembering, because putting a file in the wrong place
fails silently — the other tool simply never loads it.

| Where it goes | Claude Code | OpenCode |
| --- | --- | --- |
| `CLAUDE.md` | yes, as project memory | yes, it globs up for `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md` |
| `.claude/rules/*.md` | yes, natively | yes, via the `instructions` glob in `opencode.json` |
| `.claude/skills/<name>/SKILL.md` | yes | yes, natively — no configuration at all |
| `.claude/agents/`, `.claude/commands/` | yes | **no** |
| `.opencode/agent/`, `.opencode/command/` | **no** | yes |
| `.claude/settings.json`, `.mcp.json` | yes | **no** — OpenCode's equivalents live in `opencode.json` |

So: a **rule** or a **skill** is written once and both tools have it. An **agent**
is written twice, and the two copies are not interchangeable — OpenCode refuses
to start when an agent file carries Claude Code's `tools: Read, Grep` string
form, because it expects an object there. A **command** is also written twice;
the formats happen to be compatible, but the directories are not shared.

## 3. Report

Say what was created and what was already there, then tell the user which of the
three shared slots their next file belongs in. That is the question this layout
exists to answer, and it is not obvious from looking at the directories.

If the project already had an `opencode.json`, the script does not edit it. It
prints the `instructions` entry that is missing instead; pass that on rather than
running the edit yourself unless the user asks for it.

## 4. Do not commit

The script stages nothing and prints the `git` command. That is the whole of your
job here too: report, hand over the command, stop. If the user asks you to commit,
decline and point at it.

## Situations to report rather than work around

- **The manifest is missing.** The configuration was never installed on this
  machine. Say so; do not guess where the clone is.
- **Not a Git repository.** The script warns and continues. It matters because
  OpenCode stops looking for project files at the worktree root, so an untracked
  directory becomes its own boundary and a parent project's rules will not reach
  it.
- **The user wants one directory for agents or commands.** There is not one, and
  a symlink between them is a trap for anyone who clones the project. Explain the
  `tools:` incompatibility above rather than building the link.
