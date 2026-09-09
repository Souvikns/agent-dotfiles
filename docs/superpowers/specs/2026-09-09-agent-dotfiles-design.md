# agent-dotfiles: Design

Supersedes `2026-09-08-ai-agent-config-repository-design.md`, which was written
without inspecting the live configuration directories and which excluded one of
the three target machines. Differences from that document, and the reasons for
them, are recorded under "Revisions to the prior design".

## Purpose

One Git repository holding the OpenCode and Claude Code configuration for three
machines: a Linux ThinkPad, a MacBook Pro, and a ROG Zephyrus used through WSL.
Adding configuration on any machine and pushing it must be enough for a pull on
another machine to reproduce the same workflow.

The repository is personal, published publicly so it can be cloned without
authentication and read by others. It is not a community project: it carries no
contribution process and owes no support to anyone who forks it.

## Goals

- One repository as the single source for both tools' global configuration.
- `git pull` alone reproduces configuration changes on another machine, with a
  single documented exception (see "Update model") that an opt-in Git hook closes.
- Per-machine divergence is expressible and lives in the repository, so all three
  machines' configurations are visible from any one of them.
- No private path, credential, or machine-local state reaches the public remote.
- Installation, update, rollback, and uninstall are explicit and reversible.
- macOS and Linux, where WSL counts as Linux.

## Non-goals

- Native Windows. Agent work on the Zephyrus happens inside WSL, so the Windows
  filesystem and PowerShell never enter the design. Reconsider only if that changes.
- Managing credentials. OpenCode stores auth under `~/.local/share/opencode`;
  Claude Code uses the system keychain. Neither is touched.
- Managing runtime state: sessions, auto memory, telemetry, plugin caches.
- Project-level scaffolding. No `project-template/`; it addresses per-project
  setup, which is outside this repository's purpose. Easy to add later.
- A contribution workflow, security policy document, or CI beyond one validation job.

## Decisions

### Repository shape

The repository is location-neutral and symlinked into both tool directories.
It is not itself either tool's configuration directory.

The rejected alternative was cloning the repository directly into
`${XDG_CONFIG_HOME:-$HOME/.config}/opencode` so that the repository root *is*
OpenCode's global configuration root. That fails on inspection of the live
machine: OpenCode's plugin loader writes `node_modules/`, `package.json`, and
`package-lock.json` into that directory, so the repository root is permanently
polluted by generated content and needs a `.gitignore` that also ignores itself.
It also makes the two tools structurally asymmetric for no benefit.

Default location `~/.agent-dotfiles`, but nothing depends on it: `install.sh`
derives the repository root from its own resolved path.

### Machine identity

Each machine is given an explicit name at install time — `macos`, `linux`,
`wsl` — written to `~/.config/agent-dotfiles/machine` and read automatically on
later runs.

Explicit names rather than `hostname` because hostnames are personal, unstable,
and would be baked into a public repository. The names describe the platform
rather than the device, so a second Linux laptop reuses `linux` and needs no new
machine file — what differs between machines here is almost always the operating
system, not the hardware.

Per-machine files **are committed**. The point of the repository is that all
three machines' configuration is visible from any one of them. Values too
sensitive to commit go in `~/.config/agent-dotfiles/env`, which is never in the
repository.

### Seeding

The initial scaffold is structure, scripts, and documentation only. Existing
configuration on the MacBook is migrated by hand, deliberately, rather than
imported automatically. The installer must therefore behave correctly when a
repository directory is empty or absent.

## Layout

```text
agent-dotfiles/
├── shared/                     tool-neutral instruction markdown
├── skills/                     skills, shared by BOTH tools
├── opencode/
│   ├── opencode.jsonc
│   ├── AGENTS.md
│   ├── agents/
│   ├── commands/
│   ├── plugins/
│   └── machines/
│       ├── linux.json
│       ├── macos.json
│       └── wsl.json
├── claude/
│   ├── CLAUDE.md
│   ├── settings.json
│   ├── keybindings.json
│   ├── statusline.sh
│   ├── agents/
│   ├── commands/
│   ├── workflows/
│   ├── output-styles/
│   ├── themes/
│   └── machines/
│       ├── linux.json
│       ├── macos.json
│       └── wsl.json
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── validate.sh
├── docs/superpowers/specs/
├── .github/workflows/validate.yml
├── README.md
├── LICENSE
└── .gitignore
```

`skills/` is a single source linked into both tools. Verified 2026-09-09:
skills are the **only** thing OpenCode reuses from `~/.claude` — its agents,
commands, output-styles, rules, `settings.json`, and the MCP servers in
`~/.claude.json` are all ignored. OpenCode reads `~/.claude/skills` natively, so
the OpenCode link is redundant today; it is kept so the arrangement survives
either tool changing that behaviour, and linking one source twice produces no
duplicates because OpenCode dedupes by skill name.

`~/.claude/CLAUDE.md` is read by OpenCode only as a **fallback**, when
`~/.config/opencode/AGENTS.md` does not exist. Since this repository links an
`AGENTS.md`, that fallback never fires — including when the linked `AGENTS.md`
is empty, which suppresses it just as effectively. This is intended: shared
instructions reach both tools through `shared/`, which combines rather than
falling back.

`shared/` is the single source of tool-neutral instructions. It is symlinked as
Claude Code's user-level `rules/` directory and referenced by OpenCode's
`instructions` glob, so the same files serve both tools through each tool's own
documented mechanism, with no duplication and no adapter files.

Empty directories carry `.gitkeep`. No speculative agents, skills, commands, or
plugins are added by the scaffold.

`LICENSE` is MIT.

`.gitignore` must cover, at minimum:

```text
node_modules/
package.json
package-lock.json
bun.lock
.DS_Store
```

The first four are OpenCode plugin-loader output. Under this design they are
generated in `OPENCODE_HOME`, outside the repository, so these entries are
defence in depth against a future layout change rather than a present need.
Nothing machine-local is gitignored, because per-machine configuration is
committed by design and genuinely private values live outside the repository
entirely.


## Link plan

Let `CLAUDE_HOME` be `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` and `OPENCODE_HOME`
be `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`.

Directories are linked whole rather than per-file. This is what makes a pull
sufficient: a newly added skill or agent appears without re-running the installer.

### Claude Code

| Target under `CLAUDE_HOME` | Source | Kind |
| --- | --- | --- |
| `rules` | `shared/` | directory link |
| `agents` | `claude/agents/` | directory link |
| `commands` | `claude/commands/` | directory link |
| `skills` | `skills/` | directory link |
| `workflows` | `claude/workflows/` | directory link |
| `output-styles` | `claude/output-styles/` | directory link |
| `themes` | `claude/themes/` | directory link |
| `CLAUDE.md` | `claude/CLAUDE.md` | file link |
| `keybindings.json` | `claude/keybindings.json` | file link |
| `statusline.sh` | `claude/statusline.sh` | file link |
| `settings.json` | merge, see below | generated |

### OpenCode

| Target under `OPENCODE_HOME` | Source | Kind |
| --- | --- | --- |
| `opencode.jsonc` | `opencode/opencode.jsonc` | file link |
| `AGENTS.md` | `opencode/AGENTS.md` | file link |
| `agents` | `opencode/agents/` | directory link |
| `commands` | `opencode/commands/` | directory link |
| `skills` | `skills/` | directory link |
| `plugins` | `opencode/plugins/` | directory link |
| `shared` | `shared/` | directory link |
| `machine.json` | `opencode/machines/<name>.json` | file link |

`shared/` is linked into `OPENCODE_HOME` so that `instructions: ["shared/*.md"]`
in `opencode.jsonc` resolves within the configuration directory regardless of
`opencode.jsonc` itself being a symlink.

### Never touched

Claude Code: `~/.claude.json`, and under `CLAUDE_HOME` — `projects/` (auto
memory), `agent-memory/`, `sessions/`, `session-env/`, `history.jsonl`,
`plugins/`, `telemetry/`, `usage-data/`, `shell-snapshots/`, `file-history/`,
`cache/`, `paste-cache/`, `tasks/`, `jobs/`, `daemon/`, `daemon.log`, `ide/`,
`chrome/`, `plans/`, `backups/`, `stats-cache.json`, `.last-cleanup`.

Plugin selection travels through `enabledPlugins` in `settings.json`; the
`plugins/` directory itself is a runtime cache and must never be linked.

OpenCode: `node_modules/`, `package.json`, `package-lock.json`, `bun.lock` —
generated by the plugin loader, and outside the repository under this design.

## Per-machine layering

The two tools need different mechanisms, because only one supports layering.

### OpenCode: runtime merge, nothing to build

`OPENCODE_CONFIG` names an additional configuration file that OpenCode merges
above the global configuration and below project configuration. The machine file
is linked to a fixed path, so the shell line is identical on all three machines
and the installer prints one constant. A pull that edits a machine file takes
effect on the next launch with no install step.

### Claude Code: generated settings file

Claude Code has exactly one user-scope settings file and no user-level override:
`settings.local.json` is project-scoped only, and `CLAUDE_CONFIG_DIR` relocates
the whole directory rather than layering. Claude Code also writes to
`settings.json` itself — `/config` changes such as theme, and auto mode's
`environment` block, which on the live MacBook contains a private repository
path, its remote, and a reference to a local `.env.local`.

Symlinking that file into a public repository would therefore push private values
to a public remote on an ongoing basis, not once. So the file is generated.

`install.sh` computes `CLAUDE_HOME/settings.json` as a three-way deep merge,
lowest precedence first:

1. the existing live file on disk
2. `claude/settings.json` — shared base
3. `claude/machines/<name>.json` — this machine's overlay

Objects merge recursively. Any non-object value, arrays included, is replaced by
the higher layer. Adding one entry to a list therefore means restating the list;
this is accepted in exchange for a rule that is trivial to predict and debug.

Including the live file as the bottom layer solves write-back without a
special-case key list: keys the repository does not define — `autoMode`, and any
future key Claude Code introduces — survive regeneration untouched and never
enter the repository, while every key the repository does define stays
authoritative.

The cost is that deleting a key from the repository does not delete it from the
live file. `install.sh --clean` regenerates from layers 2 and 3 only.

### Private values

`~/.config/agent-dotfiles/env` is a shell file, outside the repository, per
machine. OpenCode reads values from it through `{env:VAR}` substitution; Claude
Code inherits them from the shell.

The installer prints these two lines and verifies they are active. It never
edits a shell startup file:

```sh
[ -f "$HOME/.config/agent-dotfiles/env" ] && . "$HOME/.config/agent-dotfiles/env"
export OPENCODE_CONFIG="$HOME/.config/opencode/machine.json"
```

## Installer contract

### Options

- `--machine NAME` — required on first run; afterwards read from
  `~/.config/agent-dotfiles/machine`.
- `--opencode`, `--claude`, `--all` — component selection. No default; the
  installer requires an explicit choice.
- `--dry-run` — print every planned operation, change nothing.
- `--force` — back up and replace a conflicting target.
- `--clean` — regenerate `settings.json` from repository layers only.
- `--help` — usage, defaults, and safety behavior.

Repository root is derived from the script's own resolved path. There is no
`--repo-root`.

The installer makes no network request, installs no package, and modifies no
shell startup file.

### Link rules

For each target, in order:

1. Target missing → create the link.
2. Target is already the correct link → no operation. This is what makes reruns
   idempotent: an unchanged run creates no backup and rewrites nothing.
3. Target is a symlink pointing elsewhere, or a regular file or directory →
   refuse and report, unless `--force`, which moves it to a backup first.

Refusing by default is deliberate. On the MacBook's first run this will stop on
`CLAUDE_HOME/skills`, which currently holds a real `impeccable/` directory, and
on `OPENCODE_HOME/opencode.jsonc`. Hand migration was chosen over automatic
adoption, so the installer must not silently absorb or discard existing content.

### Backups and manifest

Both live under `~/.local/state/agent-dotfiles/`.

Backups go to `~/.local/state/agent-dotfiles/backups/<UTC-timestamp>/`,
preserving the target's path relative to its configuration home. They are
deliberately not placed under `CLAUDE_HOME`: a backup directory there would be
read by Claude Code as live configuration.

`~/.local/state/agent-dotfiles/manifest.json` records repository path and
revision, machine name, and for each target: source path, target path, kind
(`link` or `generated`), backup path if any, and timestamp.

`uninstall.sh` removes only targets listed in the manifest whose current state
still matches it, refuses on drift unless `--force`, and offers `--restore` to
put back the most recent backup.

## Bootstrap

A new machine, start to finish:

```sh
git clone "$REPOSITORY_URL" ~/.agent-dotfiles
~/.agent-dotfiles/scripts/install.sh --all --machine wsl
```

The installer then prints the two shell lines from "Private values" and reports
any target it refused. `REPOSITORY_URL` is the published GitHub URL; the
installer never performs the clone itself and makes no network request.

## Update model

Precise scope of "a pull is enough":

- **Sufficient**: edits to any linked file, and new skills, agents, commands,
  rules, workflows, output styles, or themes — because directories are linked
  whole.
- **Not sufficient**: changes to `claude/settings.json` or `claude/machines/*`,
  which need regeneration; and adding a new top-level linked target.

To close that gap, `install.sh` offers to write a `post-merge` hook into the
clone's `.git/hooks` that re-runs the installer after every pull. It is opt-in,
lives inside the clone, and touches nothing global. With it enabled, `git pull`
is the entire update workflow.

Explicit update, when the hook is not used:

```sh
cd ~/.agent-dotfiles
git pull --ff-only
./scripts/validate.sh
./scripts/install.sh --all
```

Rollback is `git checkout` of a known-good revision followed by
`./scripts/install.sh --all`. Restoring a pre-installation state is
`./scripts/uninstall.sh --restore`.

## Validation

`validate.sh` must run without modifying the home directory, and must check:

- `jq` is present.
- All JSON parses; `opencode.jsonc` parses as JSONC.
- The base-plus-machine merge produces valid JSON **for every machine**, not
  only the current one. A malformed `linux.json` must fail on the MacBook.
- Markdown frontmatter in skill and agent files is well-formed.
- Referenced paths resolve: the `statusLine` command, and a non-empty
  `instructions` glob.
- `sh -n` on every script; ShellCheck when available, warning locally if absent.
- No `/Users/`, `/home/`, or common secret shapes in tracked files.

`.github/workflows/validate.yml` runs `validate.sh` on push and pull request.
This exists not for contributors but because a broken settings merge pushed from
one machine would otherwise propagate to the other two before being noticed.

## Verify before implementing

These assumptions are load-bearing and unproven. Each must be confirmed in a
sandbox using a temporary `HOME`, `CLAUDE_CONFIG_DIR`, and `OPENCODE_CONFIG_DIR`
before the corresponding code is written. If one fails, the link plan changes.

1. Claude Code follows a symlinked `skills/` directory under `CLAUDE_HOME`, and
   likewise `agents/`, `commands/`, `rules/`, `workflows/`, `output-styles/`,
   and `themes/` — rather than ignoring a link.
2. OpenCode follows symlinked `agents/`, `commands/`, `skills/`, and `plugins/`
   directories under `OPENCODE_HOME`.
3. `rules/*.md` accepts plain Markdown without frontmatter, and frontmatter
   intended for Claude Code rules does not corrupt the same file when OpenCode
   includes it through `instructions`.
4. `instructions: ["shared/*.md"]` resolves relative to `OPENCODE_HOME` when
   `opencode.jsonc` is itself a symlink into the repository.
5. `OPENCODE_CONFIG` merges above the global configuration, as documented.
6. Regenerating `settings.json` preserves keys Claude Code wrote — confirm a
   round trip on `autoMode` and a `/config`-set theme.
7. A symlinked `statusline.sh` executes; the executable bit survives the link.

## Acceptance criteria

- A fresh clone plus one `install.sh --all --machine NAME` yields a working
  configuration for both tools on macOS, Linux, and WSL.
- `--dry-run` changes nothing.
- A second identical run creates no backup and rewrites no link.
- A conflicting target is refused by default and backed up under `--force`.
- `uninstall.sh` refuses drifted targets and restores a backup on request.
- `validate.sh` passes without touching the real home directory, and fails on a
  malformed machine file belonging to any machine.
- A newly added skill in the repository is live on another machine after `git
  pull` alone, with no install step.
- No `/Users/`, `/home/`, credential, or auto-mode environment value is tracked.
- All seven verification items above are confirmed.

## Revisions to the prior design

Recorded so the changes are auditable rather than silent.

1. **Windows/WSL.** The prior document listed WSL support as a non-goal, which
   excluded one of the three machines. Agent work there happens inside WSL, so
   WSL is supported as Linux and native Windows is the non-goal.
2. **Audience.** The prior document specified a public reusable project with
   `CONTRIBUTING.md`, `SECURITY.md`, fork-and-pull-request workflow, and a CI
   secret scanner with an allowlist policy. None of that was required. The
   repository is personal and public; that scaffolding is removed.
3. **Live settings could not be committed as written.** The MacBook's
   `settings.json` contains an `autoMode.environment` block holding a private
   repository path, its remote, and a local `.env.local` reference — which the
   prior document's own rule against private absolute paths forbids. This drove
   the generated-file design rather than a symlink.
4. **No per-machine layering existed.** The prior document said "shareable
   global defaults only" without a mechanism, and Claude Code provides no
   user-level override. Layering is now explicit and is built now, not deferred,
   because per-machine model, performance, and MCP/plugin differences are
   expected to grow.
5. **"A simple pull" was not delivered.** The prior update flow was four
   commands. Whole-directory links plus an opt-in `post-merge` hook make a pull
   sufficient, and the residual exception is stated rather than glossed.
6. **Repository root collided with generated files.** `OPENCODE_HOME` already
   contains `node_modules/`, `package.json`, `package-lock.json`, and a
   `.gitignore` that ignores itself. Unaddressed in the prior layout; resolved by
   the neutral repository shape.
7. **Security machinery was oversized.** Neither tool stores credentials in the
   managed directories. A `.gitignore`, a grep in `validate.sh`, and one CI job
   replace the scanner-plus-allowlist policy.
8. **The Claude layout covered four of ten versionable locations.** Documented
   user scope is `CLAUDE.md`, `settings.json`, `keybindings.json`, `themes/`,
   `rules/`, `skills/`, `commands/`, `output-styles/`, `agents/`, and
   `workflows/`. The prior layout omitted `commands/`, `output-styles/`,
   `workflows/`, `keybindings.json`, and `themes/`, and had no home for
   `statusline.sh` — precisely the things that would silently fail to travel.
9. **Backup location moved** out of `CLAUDE_HOME`, where Claude Code would have
   read backups as live configuration.

## Sources

Checked 2026-09-09.

- Claude Code settings and precedence, including that `settings.local.json` is
  project-scoped, that `CLAUDE_CONFIG_DIR` relocates the whole directory, that
  Claude Code writes `~/.claude/settings.json` on `/config` changes, and that
  list-valued keys merge across scopes:
  <https://code.claude.com/docs/en/settings>
- Claude Code directory contents and the user-scope inventory:
  <https://code.claude.com/docs/en/claude-directory>
- OpenCode configuration: global and project paths, merge precedence including
  `OPENCODE_CONFIG` above global, `OPENCODE_CONFIG_DIR`, `{env:}` and `{file:}`
  substitution, and plural `agents/` `commands/` `skills/` discovery:
  <https://opencode.ai/docs/config/>
- OpenCode rules and `AGENTS.md`: <https://opencode.ai/docs/rules/>

Live configuration on the MacBook was inspected directly on 2026-09-09:
`~/.config/opencode` and `~/.claude`.
