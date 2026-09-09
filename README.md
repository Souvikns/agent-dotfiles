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
opencode/          OpenCode's global config: opencode.jsonc, AGENTS.md,
                   agents/, commands/, skills/, plugins/
opencode/machines/ per-machine OpenCode overrides
claude/            Claude Code's global config: CLAUDE.md, settings.json,
                   keybindings.json, statusline.sh, agents/, commands/,
                   skills/, workflows/, output-styles/, themes/
claude/machines/   per-machine Claude Code overrides
scripts/           install.sh, uninstall.sh, validate.sh
```

`shared/` is one directory serving both tools through each tool's own
documented mechanism, so no instruction text is duplicated.

## Install

```sh
git clone https://github.com/Souvikns/agent-dotfiles.git ~/.agent-dotfiles
~/.agent-dotfiles/scripts/install.sh --all --machine macbook
```

Use `thinkpad`, `macbook`, or `zephyrus-wsl` as the machine name. It is
remembered, so later runs need no `--machine`.

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
