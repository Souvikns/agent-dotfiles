# AI Agent Configuration Repository Design

## Purpose

Create a public repository named `ai-agent-config` that version-controls a
personal but reusable configuration for OpenCode and Claude Code. The
repository must be useful to its owner, understandable to other developers,
safe to clone, and easy to adopt selectively on macOS and Linux.

This repository is a configuration distribution project, not an application
and not a replacement for either OpenCode or Claude Code. It should expose
configuration as readable files, use the tools' documented discovery paths,
and keep credentials and machine-specific state outside Git.

## Goals

- Provide one GitHub repository for OpenCode and Claude Code configuration.
- Share tool-neutral instructions without pretending their configuration
  schemas are interchangeable.
- Make the repository root directly usable as OpenCode's global configuration
  directory when cloned to `~/.config/opencode`.
- Provide a safe installer for Claude Code's global files under `~/.claude`.
- Support macOS and Linux in the first release.
- Make installation, update, rollback, uninstall, and validation explicit.
- Let users install OpenCode only, Claude Code only, or both.
- Make additions reviewable through normal GitHub pull requests and CI.
- Give another implementation agent enough detail to scaffold the repository
  without making architectural decisions.

## Non-goals

- Windows or WSL support in the first release.
- Managing API keys, OAuth sessions, provider credentials, or personal MCP
  authentication state.
- Replacing project-level `AGENTS.md`, `CLAUDE.md`, or project settings.
- Automatically installing third-party plugins, MCP servers, CLIs, or model
  providers without an explicit user action.
- Building a general-purpose package manager for agent configurations.
- Managing Claude Code's auto-memory, trust state, or `.claude.json`.

## Product Decisions

### Repository visibility and license

The repository is public and uses the MIT license. Public files must be
treated as documentation and executable configuration that anyone can inspect.
No file may rely on a private absolute path, private organization name, or
secret value.

### Supported operating systems

The first release supports macOS and Linux with POSIX shell scripts. Scripts
must use a portable shell subset and must not assume Bash-only features unless
the script explicitly invokes Bash and checks that Bash is available.

The implementation must use these path rules:

- OpenCode global configuration: `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`.
- Claude Code global configuration: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`.
- Repository default location: `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`.
- No credentials are stored in either configuration directory by this repo.

### Repository root convention

The repository root is the OpenCode global configuration root. This follows
the public OpenCode configuration pattern of cloning a configuration repo
directly into `~/.config/opencode`.

The repository's Claude Code files live below `claude/` and are linked into
the Claude Code directory by the installer. This prevents Claude's settings
schema from being confused with OpenCode's schema while keeping both systems
in one Git history.

## Repository Layout

The implementation agent must scaffold this layout:

```text
ai-agent-config/
├── AGENTS.md
├── opencode.jsonc
├── agents/
├── commands/
├── skills/
├── plugins/
├── shared/
│   ├── principles.md
│   ├── workflow.md
│   └── security.md
├── claude/
│   ├── CLAUDE.md
│   ├── settings.json
│   ├── agents/
│   ├── rules/
│   └── skills/
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   └── validate.sh
├── project-template/
│   ├── AGENTS.md
│   ├── CLAUDE.md
│   ├── opencode.json
│   └── claude-settings.json
├── .github/
│   └── workflows/
│       └── validate.yml
├── README.md
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── .gitignore
```

Empty extension directories should contain `.gitkeep` only when required to
preserve the intended structure. The initial scaffold should not add
speculative agents, skills, plugins, MCP servers, or commands.

## Configuration Boundaries

### Shared instructions

`shared/` contains concise, tool-neutral Markdown. It defines principles,
workflow expectations, and security rules that can apply to both tools.

`AGENTS.md` and `claude/CLAUDE.md` are adapters. They must explain how each
tool uses the shared material and must not duplicate a large policy body.

OpenCode loads shared files through the `instructions` field in
`opencode.jsonc`. Claude Code loads its shared files through documented
Markdown file references. The installer must make the referenced shared path
available from the Claude configuration directory and validate that the links
resolve.

### OpenCode files

- `AGENTS.md`: global behavior and workflow rules.
- `opencode.jsonc`: schema reference, sharing preference, permissions,
  instructions, and only deliberately selected providers or models.
- `agents/`: reusable global OpenCode agent definitions.
- `commands/`: reusable global commands.
- `skills/`: reusable OpenCode skills.
- `plugins/`: local plugins only when their value is demonstrated and their
  dependency/security impact is documented.

OpenCode project configuration is intentionally not installed globally by the
Claude installer. A project's `opencode.json` belongs in that project.

### Claude Code files

- `claude/CLAUDE.md`: global Claude Code instructions.
- `claude/settings.json`: shareable global defaults only.
- `claude/agents/`: global Claude Code subagents.
- `claude/rules/`: global rules, preferably path-scoped when applicable.
- `claude/skills/`: global skills.

The repository must never manage `settings.local.json`, `.claude.json`,
project trust state, session history, or auto-memory.

### Project template

`project-template/` documents what users may copy into an application repo.
It must remain a template and must not be automatically injected into every
project by the global installer.

- `AGENTS.md` describes project-specific commands, structure, and conventions.
- `CLAUDE.md` provides the equivalent Claude Code entry point.
- `opencode.json` contains project-scoped OpenCode configuration examples.
- `claude-settings.json` is an example source for `.claude/settings.json`.

The template must state clearly that project-specific facts belong in the
application repository and should be reviewed before committing.

## Installation Contract

### Recommended installation

The README must document this as the canonical flow:

```sh
git clone "$REPOSITORY_URL" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
"${XDG_CONFIG_HOME:-$HOME/.config}/opencode/scripts/install.sh" --claude
```

`REPOSITORY_URL` represents the published GitHub URL supplied by the user. The
installer must also support running from a clone located elsewhere with an
explicit `--repo-root` option, so users do not have to move an existing
configuration repository.

### Installer modes

`install.sh` must support:

- `--opencode`: verify or link the repository as the OpenCode global root.
- `--claude`: install Claude Code files and shared-file links.
- `--all`: perform both integrations.
- `--dry-run`: print every planned operation without changing files.
- `--force`: replace managed targets only after backing them up; never replace
  unrelated files silently.
- `--repo-root PATH`: use a repository location other than the default.
- `--help`: show usage, defaults, and safety behavior.

The default mode should be conservative: require an explicit component flag
or use `--all` only when the user requests it. The installer must not make
network requests, install packages, or modify shell startup files.

### Linking and backups

The installer should use symlinks for repository-managed files and directories
so a Git pull updates the active configuration without a second synchronization
step. It must manage individual targets rather than replacing the entire
`~/.claude` directory.

Before changing a non-symlink target, the installer must move it into a
timestamped backup directory under the configuration home, for example:

```text
~/.claude-ai-agent-config-backups/2026-09-08T120000Z/
```

The backup must preserve the original file contents and relative target path.
Existing symlinks owned by another location must not be overwritten without
`--force`.

The installer must write a manifest containing:

- repository path and revision, when available;
- managed target path;
- source path;
- target type (file, directory, or shared reference);
- backup path, if a backup was made;
- installation timestamp.

The manifest allows `uninstall.sh` to remove only targets created by this
repository. Uninstall must refuse to remove a target whose current link or
content no longer matches the manifest unless `--force` is supplied.

### Updates and rollback

The README must define this update workflow:

```sh
cd "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
git pull --ff-only
./scripts/validate.sh
./scripts/install.sh --dry-run --all
./scripts/install.sh --all
```

The installer must be idempotent. Re-running it should not create repeated
backups or alter unchanged links. Rollback is performed with Git by checking
out a known-good revision, running validation, and re-running the installer.
The README must document how to restore a backup if a configuration update
breaks a user's setup.

## Security Model

The public repository must include `SECURITY.md` with these rules:

- Never commit API keys, access tokens, OAuth data, cookies, private keys, or
  provider-specific credential files.
- Use environment variables or external secret files referenced by supported
  configuration substitution mechanisms.
- Treat MCP servers, plugins, hooks, and shell commands as executable code.
- Review every permission rule for least privilege.
- Do not use broad allow rules such as unrestricted shell access merely for
  convenience.
- Do not use `curl | sh` installation instructions.
- Report accidentally committed secrets immediately and rotate them; removing
  a value in a later commit is not sufficient.

`opencode.jsonc` and `claude/settings.json` must contain placeholders or
  environment-variable references rather than credential values. CI must scan
  tracked text files for common secret patterns and fail with an actionable
  message. The scanner must support an explicit, documented allowlist for
  harmless examples.

## Validation and CI

### Local validation

`validate.sh` must be safe to run without modifying the home directory. It
must check:

- required files and directories exist;
- OpenCode JSON/JSONC is parseable and includes the expected schema URL;
- Claude settings are valid strict JSON;
- Markdown frontmatter in agent and skill files is syntactically valid;
- referenced instruction files exist;
- scripts pass shell syntax checks;
- repository files do not contain obvious secrets, private absolute paths, or
  machine-specific usernames;
- installer help and dry-run paths execute successfully.

Validation should use widely available tools where practical. If an optional
tool such as `shellcheck` is unavailable, the script may report a warning for
local use, but CI must install and run the complete validator set.

### GitHub Actions

`validate.yml` must run on pull requests and pushes to the default branch. It
must:

- check out the repository;
- install pinned validation dependencies if needed;
- run `scripts/validate.sh`;
- run ShellCheck for shell scripts;
- run installer tests in isolated temporary `HOME`, `XDG_CONFIG_HOME`, and
  `CLAUDE_CONFIG_DIR` directories;
- verify dry-run, backup, idempotence, conflict refusal, and uninstall cases;
- fail if tracked files contain disallowed secret-like values.

CI must not connect to real MCP servers, providers, or user home directories.

## GitHub Workflow

### Initial publication

The implementation agent must document this sequence rather than automate
GitHub authentication:

1. Create an empty public GitHub repository named `ai-agent-config`.
2. Add the scaffold and validate locally.
3. Review all tracked files for secrets and machine-specific values.
4. Commit the initial scaffold with a concise conventional commit message.
5. Add the GitHub remote and push the default branch.
6. Enable the validation workflow and confirm the first run passes.

The repository must include contribution instructions for fork-and-pull-request
changes. Contributors must be told not to add personal credentials, private
paths, or unreviewed third-party integrations.

### Adding new configuration

Every new agent, skill, command, hook, plugin, MCP server, or permission rule
must include:

- a focused purpose;
- the intended scope (shared, OpenCode-only, Claude-only, or project template);
- security and side-effect notes;
- usage documentation;
- validation coverage where behavior is executable;
- a pull request review.

The default should be to add Markdown guidance before adding executable hooks,
plugins, or external services.

## Documentation Requirements

`README.md` must explain:

- what the repository contains and does not contain;
- supported operating systems;
- the directory structure;
- the canonical clone and install flow;
- component-selective installation;
- dry-run, backup, update, rollback, and uninstall behavior;
- how to configure secrets safely;
- how to add project-level configuration;
- how to validate locally;
- how others can fork and customize the repository.

`CONTRIBUTING.md` must explain the change workflow, validation commands,
security review, and pull-request expectations. `SECURITY.md` must explain
secret handling and reporting. The README must link to the official
documentation used by the project:

- OpenCode config: <https://opencode.ai/docs/config/>.
- OpenCode rules: <https://opencode.ai/docs/rules/>.
- Claude Code settings: <https://code.claude.com/docs/en/settings>.
- Claude Code directory: <https://code.claude.com/docs/en/claude-directory>.


## Alternatives Considered

### Separate repositories

One repository for OpenCode and another for Claude Code would mirror each
tool's native structure but duplicate shared guidance, release notes, and
installation documentation. It also makes coordinated updates harder. This
is rejected for the first release.

### Generic repository plus custom loader

A repository with arbitrary source directories and a custom loader could
normalize both tools, but it would hide the tools' documented conventions and
create an additional runtime dependency. This is rejected in favor of using
OpenCode's root convention and a narrow Claude installer.

### Copy-based installation

Copying files is simpler initially but creates drift: Git updates do not update
the active configuration, and users cannot easily identify which files are
managed. Symlinks with backups and a manifest provide better update and
uninstall behavior while retaining an escape hatch for users who choose not to
install links.

### Fully permissive starter configuration

Large community settings repositories often pre-allow hundreds of commands or
install many integrations. This repository should not copy that pattern. A
small least-privilege baseline is safer and makes customization explicit.

## Acceptance Criteria

The scaffold is ready for implementation when:

- the repository can be cloned directly into the OpenCode global config path;
- OpenCode-specific and Claude-specific files are clearly separated;
- shared instructions have one documented source and resolvable references;
- `install.sh --dry-run` makes no changes;
- installation backs up conflicts and records a manifest;
- repeated installation is idempotent;
- uninstall refuses to remove modified/unowned targets by default;
- validation runs without touching the real home directory;
- CI tests the installer in isolated macOS/Linux-compatible environments;
- no credentials or private paths are present;
- README instructions are sufficient for a new user to clone, install, update,
  rollback, and uninstall;
- another agent can implement the scaffold without choosing the repository
  structure, safety semantics, or supported platform scope.

## Sources and Evidence

Official documentation was checked on 2026-09-08.

- OpenCode documents global configuration at
  `~/.config/opencode/opencode.json`, project configuration at `opencode.json`,
  merged precedence, JSON/JSONC support, instructions, agents, plugins, and
  environment/file substitutions: <https://opencode.ai/docs/config/>.
- OpenCode documents global `~/.config/opencode/AGENTS.md`, project
  `AGENTS.md`, Claude Code compatibility, and committed project rules:
  <https://opencode.ai/docs/rules/>.
- Claude Code documents the user, shared project, and local settings scopes,
  including `.claude/settings.json`, `.claude/settings.local.json`, and
  `~/.claude/settings.json`: <https://code.claude.com/docs/en/settings>.
- Claude Code documents the project and global `.claude` directory contents,
  including `CLAUDE.md`, settings, rules, agents, and skills:
  <https://code.claude.com/docs/en/claude-directory>.

Public repository patterns were also reviewed:

- `joelhooks/opencode-config` clones directly into `~/.config/opencode` and
  versions agents, commands, plugins, knowledge, and `AGENTS.md`:
  <https://github.com/joelhooks/opencode-config>.
- `mosherozen/opencode` versions OpenCode agents, skills, commands, plugins,
  validation scripts, CI, and environment-variable-only secrets:
  <https://github.com/mosherozen/opencode>.
- `dwillitzer/claude-settings` separates shared settings from local overrides
  and documents global/project installation:
  <https://github.com/dwillitzer/claude-settings>.
