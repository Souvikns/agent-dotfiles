# agent-dotfiles

My OpenCode and Claude Code configuration, in one repository, shared across a
Linux ThinkPad, a MacBook Pro, and a ROG Zephyrus used through WSL. Add
something on one machine, push it, pull it anywhere else, and the workflow
matches.

Public so it can be cloned without authentication and read by anyone who finds
it useful. It is **not** a community project: there is no contribution process,
no support, and no promise of stability. Fork it rather than depend on it.

## What is not in here

- **No credentials.** OpenCode keeps auth under `~/.local/share/opencode`;
  Claude Code uses the system keychain. Neither is touched.
- **No runtime state**: no session history, auto memory, plugin caches,
  telemetry, or `.claude.json`.
- **Nothing machine-local that is private.** Those values live in
  `~/.config/agent-dotfiles/env`, outside the repository.

## Supported systems

macOS and Linux. WSL counts as Linux — all agent work on the Windows machine
happens inside it. Native Windows is out of scope.

Requires `git`, `jq`, and a POSIX shell. `jq` is the only hard dependency;
install it with `brew install jq` or `apt install jq`.

## Layout

```text
shared/            tool-neutral instructions; Claude Code reads these as
                   user-level rules, OpenCode as its instructions glob
skills/            skills, shared by both tools from one directory
opencode/          OpenCode's global config: opencode.jsonc, AGENTS.md,
                   agents/, commands/, plugins/
opencode/machines/ per-machine OpenCode overrides
claude/            Claude Code's global config: CLAUDE.md, settings.json,
                   keybindings.json, statusline.sh, agents/, commands/,
                   workflows/, output-styles/, themes/
claude/machines/   per-machine Claude Code overrides
scripts/           install.sh, uninstall.sh, validate.sh, sync.sh,
                   add-skill.sh, init-project.sh
```

`shared/` and `skills/` are each one directory serving both tools, so nothing
is duplicated. Skills are the only thing OpenCode reuses from `~/.claude` —
agents, commands, output-styles, and settings are read by Claude Code alone, so
those stay under `claude/`.

## Install

```sh
git clone https://github.com/Souvikns/agent-dotfiles.git ~/.agent-dotfiles
~/.agent-dotfiles/scripts/install.sh --all --machine macos
```

Use `macos`, `linux`, or `wsl` as the machine name. The names describe the
platform rather than the hardware, so the ThinkPad is `linux` and the Zephyrus is
`wsl` — that way a fourth machine on an existing platform needs no new name and
no new machine file. The name is remembered, so later runs need no `--machine`.

The installer then prints two lines to add to your shell startup file. They are
identical on every machine, and it will not edit that file for you:

```sh
[ -f "$HOME/.config/agent-dotfiles/env" ] && . "$HOME/.config/agent-dotfiles/env"
export OPENCODE_CONFIG="$HOME/.config/opencode/machine.json"
```

Install one tool only with `--claude` or `--opencode` instead of `--all`.

Preview any run without changing anything:

```sh
~/.agent-dotfiles/scripts/install.sh --all --dry-run
```

## What a pull updates by itself

Directories are symlinked whole, so **`git pull` alone** is enough for edits to
any linked file, and for *new* skills, agents, commands, rules, workflows,
output styles, and themes.

It is **not** enough for changes to `claude/settings.json` or
`claude/machines/*.json`, which must be regenerated. Close that gap once:

```sh
~/.agent-dotfiles/scripts/install.sh --hook
```

That writes a `post-merge` hook into the clone, so every `git pull` re-runs the
installer. After it, `git pull` really is the whole update workflow.

## Day to day: `/sync`

Both tools have a `/sync` command. It reports what has changed in the checkout,
then fast-forwards and reinstalls:

```sh
~/.agent-dotfiles/scripts/sync.sh          # status, then pull and reinstall
~/.agent-dotfiles/scripts/sync.sh status   # read-only
```

**It never commits.** There is no staging, commit, or push code in `sync.sh` at
all — when there is something to commit it prints the command and stops. That is
not a confirmation prompt that could be talked past; the capability is simply
absent, so an agent driving the script cannot author history on your behalf.
`pull` is `--ff-only` and refuses to merge or rebase a divergence for the same
reason.

## Adding someone else's skill

```sh
~/.agent-dotfiles/scripts/add-skill.sh owner/repo [--skill NAME] [--ref REF]
~/.agent-dotfiles/scripts/add-skill.sh --update NAME
~/.agent-dotfiles/scripts/add-skill.sh --list
```

This copies the skill into `skills/<name>/` as real files and records where it
came from in a `.source` file, pinned to the upstream commit. Because both tools
read `skills/` through a symlink into this repository, the skill is live in
Claude Code and OpenCode the moment it lands, with no install step, and reaches
your other machines on the next pull.

Do **not** use `npx skills add` for skills you want to keep. It installs by
symlinking the agent's skill directory at a copy elsewhere on the machine — and
here that directory is this repository, so the link gets committed as a relative
path that resolves to nothing anywhere else. `validate.sh` fails on any symlink
under `skills/`.

Plugins are a separate system and are **not** vendored. `claude/settings.json`
carries `enabledPlugins` and `extraKnownMarketplaces`, so every machine agrees on
which plugins it wants, but declaring a plugin does not download it: run
`claude plugin install <name>@<marketplace>` once per machine.

## Setting up a project: `/init-project`

Everything above is global. A single project usually wants its own rules, skills,
and commands too, and those live in the project rather than here. Both tools have
an `/init-project` command for that:

```sh
~/.agent-dotfiles/scripts/init-project.sh [DIR] [--settings] [--mcp] [--dry-run]
```

It writes only what is missing, so running it on a project that already has half
the layout fills in the other half and touches nothing else.

```text
CLAUDE.md              read by BOTH — Claude Code as project memory, OpenCode
                       as it globs up for AGENTS.md / CLAUDE.md / CONTEXT.md
opencode.json          OpenCode's project config; its instructions glob is what
                       points OpenCode at the shared rules below
.claude/rules/*.md     read by BOTH
.claude/skills/        read by BOTH, natively, with no configuration at all
.claude/agents/        Claude Code only
.claude/commands/      Claude Code only
.opencode/agent/       OpenCode only
.opencode/command/     OpenCode only
```

Three of the six surfaces are shared, and none of them needs a symlink: OpenCode
looks for skills in `.opencode/skills`, `.claude/skills`, **and** `.agents/skills`,
and it will read `.claude/rules/*.md` as instructions once `opencode.json` names
that glob — which is the one line the generated config exists to carry.

Agents and commands get a directory per tool because the formats are not
interchangeable. An agent file written for Claude Code, with `tools:` as a
comma-separated string, does not merely fail to load in OpenCode — it stops
OpenCode from starting: *Expected object | undefined, got "Read, Grep, Bash"*.
Commands would in fact survive being shared, but a symlinked directory inside a
project is a trap for whoever clones it next.

`.claude/settings.json` and `.mcp.json` are Claude-Code-only and are written only
with `--settings` and `--mcp`. Personal, uncommitted overrides go in
`.claude/settings.local.json`, which is worth adding to the project's
`.gitignore`.

Like every script here, it stages nothing and prints the `git` command.
See `docs/superpowers/verification-2026-09-10.md` for how each of these
behaviours was probed.

## Per-machine configuration

`claude/machines/<name>.json` and `opencode/machines/<name>.json` hold whatever
differs on one machine. They are **committed on purpose**, so every machine's
configuration is visible from any machine and you can tune the ThinkPad from the
MacBook.

The merge rule is the same for both tools: **objects merge recursively, and
every non-object value — arrays included — is replaced by the higher layer.**
Adding one entry to a list means restating the list.

OpenCode merges its machine file at runtime via `OPENCODE_CONFIG`. Claude Code
has no user-level override, so `~/.claude/settings.json` is **generated**, not
linked, from three layers, lowest first:

1. the live file already on disk
2. `claude/settings.json`
3. `claude/machines/<name>.json`

The live file sits at the bottom so that keys Claude Code writes for itself —
its auto-mode environment block, `/config` changes — survive regeneration and
never enter the repository. Claude Code rewrites that file on every startup
using an atomic rename, which would destroy a symlink; generating it is the only
correct option. To discard local accretions and rebuild from the repository
alone, use `install.sh --clean`.

## Secrets

Put them in `~/.config/agent-dotfiles/env`, which is never in the repository.
OpenCode reads them with `{env:VAR}` substitution; Claude Code inherits them
from the shell.

## Conflicts, backups, rollback

A target that is a real file, a real directory, or a symlink owned by something
else is **refused, never overwritten** — `install.sh` exits 3 and changes
nothing. Expect this on a first install where you already have configuration.

`--force` backs the conflict up first, under
`~/.local/state/agent-dotfiles/backups/<timestamp>/`, then links. Backups live
there rather than inside `~/.claude`, where Claude Code would read them as live
configuration.

```sh
scripts/uninstall.sh                # remove only what this repo installed
scripts/uninstall.sh --restore      # and put the backed-up originals back
```

Uninstall refuses any target that no longer matches its manifest, so it never
deletes something unrelated. It keeps the generated `settings.json` unless you
pass `--force`, because that file holds settings that exist nowhere else.

Roll back to a known-good revision with Git, then reinstall:

```sh
cd ~/.agent-dotfiles && git checkout <revision> && ./scripts/install.sh --all
```

## Validate

```sh
sh scripts/validate.sh   # config parses, merges, no private paths, no secrets
sh tests/run.sh          # the installer's own test suite
```

`validate.sh` never touches your home directory, and checks every machine's
merge — not just the current machine's — so a file broken here fails here rather
than after it reaches another machine.

## Forking

Replace the three files in `claude/machines/` and `opencode/machines/` with your
own machine names. Nothing else in the repository is specific to my machines.

## Documentation

- OpenCode config: <https://opencode.ai/docs/config/>
- OpenCode rules: <https://opencode.ai/docs/rules/>
- Claude Code settings: <https://code.claude.com/docs/en/settings>
- Claude Code directory: <https://code.claude.com/docs/en/claude-directory>
