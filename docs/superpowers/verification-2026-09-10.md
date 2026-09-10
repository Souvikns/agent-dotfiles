# Verification: project-level configuration in both tools

Ran 2026-09-10 on macOS 15 (Darwin 25.5.0), Claude Code 2.1.236, opencode
1.18.30. Probe projects were scratch Git repositories with a distinctly named
file in every plausible location; where a CLI could not answer, the question was
put to the tool itself.

The question behind all of it: **how much of a project's agent configuration can
be one folder rather than two?** Answer: three surfaces of six are shared, and
none of them need a symlink.

| Surface | Claude Code | OpenCode | Shared |
| --- | --- | --- | --- |
| Instructions | `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/**`, walking up | `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, walking up to the worktree; plus `instructions` globs | **Yes** — `CLAUDE.md` natively; `.claude/rules/*.md` via the glob |
| Skills | `.claude/skills/<n>/SKILL.md` | `.opencode/skills/`, `.claude/skills/`, `.agents/skills/` | **Yes**, natively, no configuration |
| Agents | `.claude/agents/*.md` | `.opencode/agent/` or `.opencode/agents/` | No |
| Commands | `.claude/commands/*.md` | `.opencode/command/` or `.opencode/commands/` | No |
| Settings | `.claude/settings.json`, `.claude/settings.local.json` | `opencode.json(c)` at the root, or `.opencode/opencode.json` | No |
| MCP | `.mcp.json` | the `mcp` key of `opencode.json` | No |

## Skills: one directory, both tools — but `debug skill` will not show it

`opencode debug skill` lists **only globally scoped skills**. Three project
skills placed in `.opencode/skills`, `.claude/skills`, and `.agents/skills` were
all absent from its output, which is what first suggested project skills were
unsupported. They are not: the server API sees all three.

```
$ opencode serve --port 4602 &
$ curl -s --get --data-urlencode "directory=$P" http://127.0.0.1:4602/skill
[('ag-proj-skill', '.../probe2/.agents/skills/ag-proj-skill/SKILL.md'),
 ('cc-proj-skill', '.../probe2/.claude/skills/cc-proj-skill/SKILL.md'),
 ('oc-proj-skill', '.../probe2/.opencode/skills/oc-proj-skill/SKILL.md')]
```

This matters beyond the immediate question: the 2026-09-09 verification used
`opencode debug skill` as its instrument, and that command is blind to project
scope. Global conclusions from it stand; project conclusions cannot be drawn
from it at all.

## Agents and commands: no shared directory, and only one of them could fake it

Probed by putting probe files in every candidate directory of a project and
reading `opencode debug config`:

- **Agents**: `.opencode/agent/` and `.opencode/agents/` are both read.
  `.claude/agents/` and `.agents/agents/` are **not**.
- **Commands**: `.opencode/command/` and `.opencode/commands/` are both read.
  `.claude/commands/` and `.agents/commands/` are **not**.

The file formats then diverge in a way that decides the design. A Claude Code
agent file dropped into `.opencode/agent/` does not merely fail to load — it
stops OpenCode from starting at all:

```
$ opencode debug config
Error: Configuration is invalid at .../.opencode/agent/cc-style-agent.md
↳ Expected object | undefined, got "Read, Grep, Bash" tools
```

Claude Code writes `tools:` as a comma-separated string; OpenCode expects an
object. Remove the `tools` key and the same file loads cleanly, with mode `all`.
Commands are the friendlier case: a Claude Code command with `argument-hint`,
`allowed-tools`, and `disable-model-invocation` loaded in OpenCode with the
unknown keys silently ignored, `$ARGUMENTS` and `` !`cmd` `` intact.

So commands *could* be shared through a symlink and agents could not. Neither is,
in the scaffold `init-project.sh` writes: a symlinked directory inside a project
is a trap for whoever clones it next, and the saving is two files.

## Instructions: relative `instructions` globs resolve against the project

This settles open question 4 from the 2026-09-09 document, and not in the
direction that document's configuration assumes. From the OpenCode binary, the
loader for a relative instruction entry is:

```js
m = function*(T) {
    if (!OPENCODE_DISABLE_PROJECT_CONFIG)
        return yield* e.globUp(T, d.directory, d.worktree);
    return yield* e.globUp(T, r.config, r.config);
}
```

and `globUp(pattern, start, stop)` globs in `start`, then in each parent, until
it passes `stop`. A relative pattern is therefore resolved **from the session
directory up to the worktree root** — never against the file that declares it.
Absolute patterns and `~/`-prefixed ones are handled separately and do work.

Two consequences:

1. For a project, `".claude/rules/*.md"` in `opencode.json` is correct and keeps
   working from any subdirectory. This is the wire the scaffold depends on.
2. For the global configuration in this repository, `"instructions": ["shared/*.md"]`
   in `opencode/opencode.jsonc` resolves against whatever project OpenCode is
   started in, so it matches nothing — except inside this repository, which
   happens to contain a `shared/` directory. **The global shared rules do not
   reach OpenCode.** `~/.config/opencode/shared/*.md` would fix it, and the
   `dir|shared|$OPENCODE_HOME/shared` target row exists to make that path real.
   Not changed here; it is a separate decision from this feature.

Claude Code's side of the same question was read out of its binary's memory
loader, which walks up the tree collecting, per directory: `CLAUDE.md` and
`.claude/CLAUDE.md` and `.claude/rules/` as Project memory, and `CLAUDE.local.md`
as Local. **`AGENTS.md` is not among them** — every occurrence of that filename in
the binary belongs to Codex migration or to the `/init` prompt. OpenCode reads
`AGENTS.md`, `CLAUDE.md`, and `CONTEXT.md`, so `CLAUDE.md` is the filename both
tools actually agree on.

## End to end: the scaffold, in both tools, answering from a shared rule

The generated project got one rule file, `.claude/rules/tokens.md`, containing a
token and an instruction to answer with it. Both tools were then asked, in that
directory:

```
$ opencode run --pure -m opencode/claude-haiku-4-5 "What is the project token? Reply with only the token."
7f3a

$ claude -p "What is the project token? Reply with only the token." --model haiku
7f3a
```

One file, written once, reaching both tools — Claude Code natively, OpenCode
through the `instructions` glob the scaffold writes. The scaffolded
`.claude/skills/` directory was confirmed the same way through the server API.

## Open questions

1. Whether `.agents/skills/` is worth adopting as the shared skills directory
   instead of `.claude/skills/`. OpenCode reads it; Claude Code does not, so it
   would need a symlink today. It is the more neutral name if Claude Code ever
   adds it.
2. Whether Claude Code tolerates OpenCode's `mode:` key in an agent file. Not
   tested, and not needed while the two agent directories stay separate.
