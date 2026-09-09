# Verification of spec assumptions

Ran 2026-09-09 on macOS 15 (Darwin 25.5.0), opencode 1.18.30, in a sandbox with
`HOME`, `CLAUDE_CONFIG_DIR`, `XDG_CONFIG_HOME`, and `XDG_STATE_HOME` redirected
to a temporary directory (`tests/sandbox.sh`).

| # | Assumption | Result |
| --- | --- | --- |
| 1 | Claude Code follows symlinked config directories | **PASS** |
| 2 | OpenCode follows symlinked config directories | **PASS** |
| 3 | `rules/*.md` accepts Markdown with and without frontmatter | **PASS** |
| 4 | `instructions` glob resolves against the config dir | **UNRESOLVED** (test invalid) |
| 5 | `OPENCODE_CONFIG` merges above the global config | **PASS** |
| 6 | Regenerating `settings.json` preserves Claude Code's own writes | **PASS**, with two surprises |
| 7 | A symlinked `statusline.sh` executes | **PASS** |

## 2 — OpenCode follows symlinked directories: PASS

`~/.config/opencode/agents` and `~/.config/opencode/skills` were symlinks to
directories elsewhere. Both were read:

```
$ opencode agent list
probe-agent (subagent)

$ opencode debug skill
  "name": "probe-skill",
  "location": ".../home/.config/opencode/skills/probe-skill/SKILL.md",
```

OpenCode reports the **symlink path**, not the resolved target, so it reads
through the link without canonicalising. The `dir` rows of the OpenCode target
table are sound.

## 5 — `OPENCODE_CONFIG` merges above global: PASS

Global config set `model` to `anthropic/GLOBAL-VALUE`; the file named by
`OPENCODE_CONFIG` set `anthropic/MACHINE-VALUE`.

```
$ opencode debug config | grep model
  "model": "anthropic/GLOBAL-VALUE",

$ OPENCODE_CONFIG=.../machine.json opencode debug config | grep model
  "model": "anthropic/MACHINE-VALUE",
```

Custom config outranks global, and unsetting the variable degrades cleanly to
the shared value. The per-machine OpenCode layer needs no code.

## 6 — Settings write-back: PASS, and stronger than the spec assumed

Two findings that matter more than the original assumption.

**Claude Code rewrites `settings.json` on every startup, not only on `/config`
changes — and it writes atomically via temp file plus rename:**

```
[DEBUG] Writing to temp file: .../.claude/settings.json.tmp.16848.756456a41baa
[DEBUG] Renaming .../settings.json.tmp.16848... to .../.claude/settings.json
[DEBUG] File .../.claude/settings.json written atomically
```

A rename **replaces** a symlink rather than writing through it. Had
`settings.json` been symlinked into the repository, Claude Code would have
destroyed the link on first launch and left a regular file in its place. The
spec chose to generate this file to avoid publishing private values; that
reasoning holds, and this is a second, independent reason the file cannot be a
symlink. Record it in the spec.

**Claude Code normalises values it writes back.** `{"model":"opus"}` came back
as `{"model":"opus[1m]"}`. Because the live file is the *lowest* precedence
layer in the three-way merge, the repository's value wins on the next install
and the normalisation is reverted. That is the intended behaviour — the
repository stays authoritative — but it means `settings.json` may differ from
the repository between an install and the next launch.

## 7 — Symlinked `statusline.sh` executes: PASS

```
$ ln -s "$REAL/statusline.sh" "$CLAUDE_CONFIG_DIR/statusline.sh"
$ [ -x "$CLAUDE_CONFIG_DIR/statusline.sh" ]   # true
$ "$CLAUDE_CONFIG_DIR/statusline.sh"          # PROBE-STATUSLINE
```

The executable bit resolves through the link and the script runs.

## 1 and 3 — PASS

A sandbox cannot verify these: Claude Code exits with `Not logged in` before it
discovers skills, agents, or rules, because redirecting `HOME` hides the
credentials, and pre-seeding `.claude.json` with `hasCompletedOnboarding` does
not get past it. They were verified instead in an authenticated session, with
`~/.claude/skills` and `~/.claude/rules` temporarily swapped for symlinks:

```
## Skills available
**Probe / project**
- `probe-skill` — temporary verification probe
```

- **1**: the symlinked `skills/` directory was read. The `dir` rows of the
  Claude target table are sound.
- **3a**: a rule file *with* YAML frontmatter loaded.
- **3b**: a rule file *without* frontmatter loaded.

Both rule forms work, so `shared/*.md` can serve as Claude Code's `rules/` and
OpenCode's `instructions` without a frontmatter convention imposed on either.

## 4 — UNRESOLVED: the test was invalid

`opencode debug config` echoes `instructions` unresolved:

```
  "instructions": [
    "shared/*.md"
  ],
```

so it does not reveal whether the glob resolves against the configuration
directory or against the repository where the symlinked `opencode.jsonc`
actually lives. Debug logging at `DEBUG` level adds nothing about instruction
loading. Deciding this needs a real session, which costs a model call.

A session-based retest was attempted and **produced no usable evidence**. The
OpenCode call ran while the Claude probe was still symlinked at
`~/.claude/skills`, and the model answered by invoking that skill rather than
reading the instruction file:

```
→ Skill "probe-skill"
PROBE-SKILL-VISIBLE
```

The absence of the instruction token reflects a hijacked question, not a failed
glob. Do not read that run as a FAIL.

**Consequence either way:** if the glob resolves against the configuration
directory, the `dir|shared|$OPENCODE_HOME/shared` row is required. If it
resolves against the repository, that row is unnecessary but harmless. Keeping
the row is safe under both outcomes, so this does not block implementation — it
only decides whether one link is redundant. The row is kept.

## Incidental finding: OpenCode appears to read `~/.claude/skills`

During the invalid assumption-4 run, OpenCode discovered and invoked
`probe-skill`. That skill existed only under `~/.claude/skills` (a symlink to
the probe directory at the time). `OPENCODE_CONFIG_DIR` pointed at a directory
with no `skills/`, and the real `~/.config/opencode` has no `skills/` either, so
`~/.claude/skills` is the only possible source.

If this holds, `claude/skills/` and `opencode/skills/` in this repository are
redundant and one directory could serve both tools. This is a single
observation and a change to the spec's layout, so it is recorded rather than
acted on. Worth a dedicated test before any consolidation.

## Open questions

1. Assumption 4 still needs a clean test: an `opencode run` with no Claude
   skills reachable, so the model cannot answer from a skill. Not blocking —
   the `shared` link is correct under either outcome.
2. Whether OpenCode really reads `~/.claude/skills`. If it does, the two skills
   directories can be consolidated.
