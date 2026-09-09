# agent-dotfiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a location-neutral Git repository that symlinks OpenCode and Claude Code global configuration into place on three machines, so that `git pull` reproduces a workflow change everywhere.

**Architecture:** Three POSIX entry-point scripts (`install.sh`, `uninstall.sh`, `validate.sh`) over a set of single-responsibility libraries under `scripts/lib/`. A declarative target table drives all linking; whole directories are linked so new files travel with a pull. Claude Code's one settings file is *generated* by a three-way deep merge rather than linked, because Claude Code writes to it and those writes contain private values. Installer state (manifest, backups) lives under `$XDG_STATE_HOME`, outside both tool directories.

**Tech Stack:** POSIX `sh`, `jq` (only hard runtime dependency), `git`, GitHub Actions. Tests use a ~40-line in-repo harness (`tests/helpers.sh`) rather than an external framework, to avoid a second dependency on all three machines.

**Spec:** `docs/superpowers/specs/2026-09-09-agent-dotfiles-design.md`

## Global Constraints

- **Shell:** POSIX `sh` only. No bashisms (no `[[`, no arrays, no `local`, no `${var,,}`). Scripts start with `#!/bin/sh` and `set -eu`.
- **Platforms:** macOS, Linux, and WSL-as-Linux. Native Windows is out of scope.
- **Portability traps:** do not use `readlink -f` (differs BSD vs GNU), `realpath` (absent on older macOS), `sed -i` (differs), `mktemp -d` without a template, or GNU-only `find` predicates. Plain `readlink` is fine.
- **Dependencies:** `jq` is the only hard runtime dependency. ShellCheck is optional locally, required in CI.
- **The installer must never:** make a network request, install a package, or modify a shell startup file.
- **Machine names:** `thinkpad`, `macbook`, `zephyrus-wsl`.
- **Path variables**, used everywhere and always via the accessors in `lib/common.sh` so tests can sandbox them:
  - `CLAUDE_HOME` = `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`
  - `OPENCODE_HOME` = `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`
  - `STATE_HOME` = `${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles`
  - `AD_CONFIG_HOME` = `${XDG_CONFIG_HOME:-$HOME/.config}/agent-dotfiles`
- **License:** MIT.
- **Merge semantics:** objects merge recursively; every non-object value, arrays included, is replaced by the higher layer.
- **Layer precedence for `settings.json`,** lowest first: live file on disk, `claude/settings.json`, `claude/machines/<name>.json`.
- **Never link:** Claude `plugins/`, `projects/`, `agent-memory/`, `sessions/`, `session-env/`, `history.jsonl`, `telemetry/`, `usage-data/`, `shell-snapshots/`, `file-history/`, `cache/`, `paste-cache/`, `tasks/`, `jobs/`, `daemon*`, `ide/`, `chrome/`, `plans/`, `backups/`, `stats-cache.json`, `.last-cleanup`, `~/.claude.json`; OpenCode `node_modules/`, `package.json`, `package-lock.json`, `bun.lock`.

---

## Task 1: Verification sandbox and Claude Code assumptions

Spec section "Verify before implementing" items 1, 3, 6, 7. **This task gates Tasks 5-12.** If any assumption fails, stop and report — the link plan changes and the spec needs revising before more code is written.

**Files:**
- Create: `tests/sandbox.sh`
- Create: `docs/superpowers/verification-2026-09-09.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/sandbox.sh` defining `sandbox_new` (prints a fresh temp dir and exports `HOME`, `CLAUDE_CONFIG_DIR`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME` inside it) and `sandbox_rm DIR`. Used by `tests/helpers.sh` in Task 3.

- [ ] **Step 1: Write the sandbox helper**

```sh
# tests/sandbox.sh — isolate every path the installer touches.
# Sourced, not executed. Callers must `eval` the export block it prints.

sandbox_new() {
    _sb=$(mktemp -d "${TMPDIR:-/tmp}/agent-dotfiles-sb.XXXXXX") || return 1
    mkdir -p "$_sb/home" "$_sb/home/.config" "$_sb/home/.local/state"
    printf '%s\n' "$_sb"
}

sandbox_env() {
    # $1 = sandbox dir. Prints an eval-able export block.
    cat <<EOF
HOME='$1/home'
CLAUDE_CONFIG_DIR='$1/home/.claude'
XDG_CONFIG_HOME='$1/home/.config'
XDG_STATE_HOME='$1/home/.local/state'
export HOME CLAUDE_CONFIG_DIR XDG_CONFIG_HOME XDG_STATE_HOME
EOF
}

sandbox_rm() {
    case "$1" in
        */agent-dotfiles-sb.*) rm -rf "$1" ;;
        *) echo "refusing to remove non-sandbox path: $1" >&2; return 1 ;;
    esac
}
```

The `case` guard exists so a bug in a caller cannot turn this into `rm -rf $HOME`.

- [ ] **Step 2: Verify assumption 1 — Claude Code follows symlinked config directories**

```sh
. tests/sandbox.sh
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
mkdir -p "$SB/real/skills/probe-skill" "$CLAUDE_CONFIG_DIR"
cat > "$SB/real/skills/probe-skill/SKILL.md" <<'EOF'
---
name: probe-skill
description: Verification probe. If this is listed, symlinked skill dirs work.
---
Reply with the exact string PROBE-SKILL-VISIBLE.
EOF
ln -s "$SB/real/skills" "$CLAUDE_CONFIG_DIR/skills"
claude -p '/skill-doctor' 2>&1 | grep -i 'probe-skill' && echo "ASSUMPTION 1 (skills): PASS" || echo "ASSUMPTION 1 (skills): FAIL"
```

Repeat the identical shape for `agents`, `commands`, `rules`, `workflows`, `output-styles`, and `themes`, each with one minimal probe file. Record PASS/FAIL per directory — they may not all behave the same, and a partial failure means those specific rows leave the link table and become generated or copied instead.

- [ ] **Step 3: Verify assumption 3 — `rules/*.md` accepts plain Markdown**

Place two files in the symlinked `rules/` directory: one with YAML frontmatter (`---\ndescription: probe\n---\n`) and one with none. Start a session and confirm neither produces a parse error and both are loaded. Frontmatter matters because the same files are consumed by OpenCode's `instructions` in Task 2.

- [ ] **Step 4: Verify assumption 6 — settings write-back round-trips**

```sh
printf '{"model":"opus"}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
# Start Claude Code, change the theme via /config, exit.
cat "$CLAUDE_CONFIG_DIR/settings.json"   # expect: model preserved, theme added
```
Confirm the written file still contains `model` and now contains `theme`. This is the premise of the three-way merge: keys the repo does not define must survive, and Claude Code must tolerate the file being rewritten underneath it between sessions.

- [ ] **Step 5: Verify assumption 7 — symlinked statusline executes**

```sh
mkdir -p "$SB/real"
printf '#!/bin/sh\nprintf "PROBE-STATUSLINE"\n' > "$SB/real/statusline.sh"
chmod +x "$SB/real/statusline.sh"
ln -s "$SB/real/statusline.sh" "$CLAUDE_CONFIG_DIR/statusline.sh"
[ -x "$CLAUDE_CONFIG_DIR/statusline.sh" ] && echo "exec bit through link: PASS" || echo "exec bit through link: FAIL"
```
Then set `"statusLine": {"type":"command","command":"~/.claude/statusline.sh"}` in the sandbox settings, start a session, and confirm `PROBE-STATUSLINE` renders.

- [ ] **Step 6: Record findings**

Write `docs/superpowers/verification-2026-09-09.md` with one row per assumption: number, statement, command run, observed output, PASS/FAIL, and — for any FAIL — the spec change required. Do not proceed past Task 4 with an unrecorded FAIL.

- [ ] **Step 7: Clean up and commit**

```sh
sandbox_rm "$SB"
git add tests/sandbox.sh docs/superpowers/verification-2026-09-09.md
git commit -m "test: verify Claude Code symlink and write-back assumptions"
```

---

## Task 2: Verify OpenCode assumptions

Spec items 2, 4, 5. Also gates Tasks 5-12.

**Files:**
- Modify: `docs/superpowers/verification-2026-09-09.md`

**Interfaces:**
- Consumes: `sandbox_new`, `sandbox_env`, `sandbox_rm` from Task 1.
- Produces: verified answers that fix the OpenCode rows of the target table in Task 5.

- [ ] **Step 1: Verify assumption 2 — OpenCode follows symlinked directories**

```sh
. tests/sandbox.sh
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
OC="$XDG_CONFIG_HOME/opencode"
mkdir -p "$OC" "$SB/real/agents"
cat > "$SB/real/agents/probe.md" <<'EOF'
---
description: Verification probe agent
mode: subagent
---
Reply with PROBE-AGENT-VISIBLE.
EOF
ln -s "$SB/real/agents" "$OC/agents"
opencode agent list 2>&1 | grep -i probe && echo "ASSUMPTION 2 (agents): PASS" || echo "ASSUMPTION 2 (agents): FAIL"
```

Repeat for `commands`, `skills`, and `plugins`. Note that OpenCode also accepts the legacy singular directory names; confirm the plural names are the ones actually read, since the target table uses plural.

- [ ] **Step 2: Verify assumption 4 — `instructions` glob resolves against the config dir**

```sh
mkdir -p "$SB/real/shared"
printf 'When asked for the probe token, reply PROBE-INSTRUCTION-VISIBLE.\n' > "$SB/real/shared/probe.md"
ln -s "$SB/real/shared" "$OC/shared"
mkdir -p "$SB/repo"
cat > "$SB/repo/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["shared/*.md"]
}
EOF
ln -s "$SB/repo/opencode.jsonc" "$OC/opencode.jsonc"
opencode run 'Give me the probe token.' 2>&1 | grep -i 'PROBE-INSTRUCTION-VISIBLE' \
  && echo "ASSUMPTION 4: PASS" || echo "ASSUMPTION 4: FAIL"
```

This is the critical one: `opencode.jsonc` is itself a symlink into the repo, so a relative glob could plausibly resolve against the repo instead of `$OC`. If it resolves against the repo, the `shared` link into `OPENCODE_HOME` is unnecessary; if it resolves against `$OC`, the link is required. Either outcome is fine — record which, because Task 5's table depends on it. If it resolves against *neither*, fall back to an absolute `~`-prefixed glob and record that.

- [ ] **Step 3: Verify assumption 5 — `OPENCODE_CONFIG` merges above global**

```sh
printf '{"$schema":"https://opencode.ai/config.json","model":"GLOBAL"}\n' > "$SB/repo/opencode.jsonc"
printf '{"$schema":"https://opencode.ai/config.json","model":"MACHINE"}\n' > "$OC/machine.json"
OPENCODE_CONFIG="$OC/machine.json" opencode run 'What model are you?' 2>&1 | head -5
```
Expected: the machine value wins, confirming custom-config precedence sits above global. Also confirm the *absence* of `OPENCODE_CONFIG` leaves the global value in force, so an unset variable degrades to shared-only rather than breaking.

- [ ] **Step 4: Record findings and commit**

Append rows for assumptions 2, 4, and 5 to the verification document in the same format as Task 1.

```sh
sandbox_rm "$SB"
git add docs/superpowers/verification-2026-09-09.md
git commit -m "test: verify OpenCode symlink, instructions, and config-merge assumptions"
```

- [ ] **Step 5: Gate check**

Re-read the verification document. If every assumption passed, continue to Task 3. If any failed, stop, update `docs/superpowers/specs/2026-09-09-agent-dotfiles-design.md` to match reality, and re-confirm the affected sections before continuing.

---

## Task 3: Repository scaffold and test harness

**Files:**
- Create: the directory tree from the spec's "Layout", each empty directory holding `.gitkeep`
- Create: `LICENSE`, `tests/helpers.sh`, `tests/run.sh`, `tests/test_harness.sh`
- Verify: `.gitignore` already lists `node_modules/`, `package.json`, `package-lock.json`, `bun.lock`, `.DS_Store` (committed alongside the spec). Add anything missing.

**Interfaces:**
- Consumes: `tests/sandbox.sh` from Task 1.
- Produces: `assert_eq MSG EXPECTED ACTUAL`, `assert_ok MSG CMD...`, `assert_fail MSG CMD...`, `assert_file MSG PATH`, `assert_link MSG LINK EXPECTED_TARGET`, and the runner `tests/run.sh` which executes every `tests/test_*.sh` and exits non-zero if any assertion failed.

- [ ] **Step 1: Create the tree**

```sh
cd ~/Documents/programs/souvikns/agent-dotfiles
mkdir -p shared \
  opencode/agents opencode/commands opencode/skills opencode/plugins opencode/machines \
  claude/agents claude/commands claude/skills claude/workflows claude/output-styles \
  claude/themes claude/machines \
  scripts/lib tests .github/workflows
for d in shared opencode/agents opencode/commands opencode/skills opencode/plugins \
         claude/agents claude/commands claude/skills claude/workflows \
         claude/output-styles claude/themes; do
    touch "$d/.gitkeep"
done
printf '{}\n' > claude/settings.json
for m in thinkpad macbook zephyrus-wsl; do
    printf '{}\n' > "claude/machines/$m.json"
    printf '{\n  "$schema": "https://opencode.ai/config.json"\n}\n' > "opencode/machines/$m.json"
done
printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "instructions": ["shared/*.md"]\n}\n' > opencode/opencode.jsonc
: > opencode/AGENTS.md
: > claude/CLAUDE.md
printf '{}\n' > claude/keybindings.json
printf '#!/bin/sh\n' > claude/statusline.sh
chmod +x claude/statusline.sh
```

The machine files are `{}` and the settings base is `{}` deliberately — the spec chose hand migration over seeding, so the scaffold ships empty but structurally complete.

- [ ] **Step 2: Write the MIT LICENSE file**

Standard MIT text, copyright `2026 Souvik`.

- [ ] **Step 3: Write the test harness**

```sh
# tests/helpers.sh
TESTS_RUN=0
TESTS_FAILED=0

_pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  ok   %s\n' "$1"; }
_fail() {
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$1"
    shift
    for _l in "$@"; do printf '       %s\n' "$_l"; done
}

assert_eq() {  # MSG EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then _pass "$1"
    else _fail "$1" "expected: $2" "actual:   $3"; fi
}

assert_ok() {  # MSG CMD...
    _m=$1; shift
    if _out=$("$@" 2>&1); then _pass "$_m"
    else _fail "$_m" "command failed: $*" "$_out"; fi
}

assert_fail() {  # MSG CMD...
    _m=$1; shift
    if _out=$("$@" 2>&1); then _fail "$_m" "expected failure, got success: $*" "$_out"
    else _pass "$_m"; fi
}

assert_file() {  # MSG PATH
    if [ -e "$2" ]; then _pass "$1"; else _fail "$1" "missing path: $2"; fi
}

assert_link() {  # MSG LINK EXPECTED_TARGET
    if [ ! -L "$2" ]; then _fail "$1" "not a symlink: $2"; return; fi
    _t=$(readlink "$2")
    if [ "$_t" = "$3" ]; then _pass "$1"
    else _fail "$1" "link target expected: $3" "link target actual:   $_t"; fi
}
```

`assert_ok` and `assert_fail` capture output so a failing command's diagnostics appear in the report rather than scrolling past.

- [ ] **Step 4: Write the runner**

```sh
#!/bin/sh
# tests/run.sh — run every tests/test_*.sh, report, exit non-zero on failure.
set -u
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

total=0
failed=0
for t in test_*.sh; do
    [ -e "$t" ] || continue
    printf '%s\n' "$t"
    out=$(sh "$t" 2>&1)
    printf '%s\n' "$out"
    n=$(printf '%s\n' "$out" | grep -c '^  \(ok\|FAIL\) ' || true)
    f=$(printf '%s\n' "$out" | grep -c '^  FAIL ' || true)
    total=$((total + n))
    failed=$((failed + f))
done

printf '\n%s assertions, %s failed\n' "$total" "$failed"
[ "$failed" -eq 0 ]
```

Note each test file runs in its own `sh` process, so a test that leaves a sandbox behind or exports a stray variable cannot contaminate the next one.

- [ ] **Step 5: Write a self-test of the harness**

```sh
#!/bin/sh
# tests/test_harness.sh
set -u
. ./helpers.sh
. ./sandbox.sh

assert_eq "assert_eq matches equal strings" "a" "a"
assert_ok "assert_ok accepts a succeeding command" true
assert_fail "assert_fail accepts a failing command" false

SB=$(sandbox_new)
eval "$(sandbox_env "$SB")"
assert_eq "sandbox redirects HOME" "$SB/home" "$HOME"
assert_eq "sandbox redirects CLAUDE_CONFIG_DIR" "$SB/home/.claude" "$CLAUDE_CONFIG_DIR"
assert_file "sandbox created config home" "$XDG_CONFIG_HOME"
sandbox_rm "$SB"
assert_fail "sandbox_rm refuses a non-sandbox path" sandbox_rm /tmp
```

- [ ] **Step 6: Run it and verify it passes**

Run: `sh tests/run.sh`
Expected: `7 assertions, 0 failed`, exit 0. If the count differs, the runner's `grep -c` is miscounting — fix that before trusting any later task.

- [ ] **Step 7: Commit**

```sh
chmod +x tests/run.sh
git add -A
git commit -m "chore: scaffold repository tree, MIT license, and POSIX test harness"
```

---

## Task 4: Paths and machine identity

**Files:**
- Create: `scripts/lib/common.sh`, `scripts/lib/machine.sh`, `tests/test_common.sh`, `tests/test_machine.sh`

**Interfaces:**
- Consumes: the test harness from Task 3.
- Produces: `ad_die`, `ad_warn`, `ad_say`, `ad_claude_home`, `ad_opencode_home`, `ad_state_home`, `ad_config_home`, `ad_timestamp`, `ad_require_jq`, `ad_repo_revision REPO`; and `ad_machine_file`, `ad_machine_save NAME`, `ad_machine_load`, `ad_machine_valid NAME`, `ad_machine_resolve [NAME]`. Every later task reaches paths only through these accessors — never by expanding `$HOME` directly — because that is what lets tests sandbox them.

**Critical shell rule for this and every following task:** with `set -e` in force, `[ cond ] && action` aborts the whole script when `cond` is false, because the `&&` list exits non-zero. Always write `if [ cond ]; then action; fi`. This bites hardest in functions where the conditional is not the last statement.

- [ ] **Step 1: Write the failing tests for paths**

```sh
#!/bin/sh
# tests/test_common.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

assert_eq "claude home honours CLAUDE_CONFIG_DIR" "$SB/home/.claude" "$(ad_claude_home)"
assert_eq "opencode home honours XDG_CONFIG_HOME" "$SB/home/.config/opencode" "$(ad_opencode_home)"
assert_eq "state home honours XDG_STATE_HOME" "$SB/home/.local/state/agent-dotfiles" "$(ad_state_home)"
assert_eq "config home honours XDG_CONFIG_HOME" "$SB/home/.config/agent-dotfiles" "$(ad_config_home)"

unset CLAUDE_CONFIG_DIR
assert_eq "claude home falls back to HOME" "$SB/home/.claude" "$(ad_claude_home)"

case "$(ad_timestamp)" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z)
        assert_eq "timestamp is UTC and filename-safe" "ok" "ok" ;;
    *)  assert_eq "timestamp is UTC and filename-safe" "ok" "$(ad_timestamp)" ;;
esac

assert_eq "repo revision of a non-repo is 'unknown'" "unknown" "$(ad_repo_revision "$SB")"

sandbox_rm "$SB"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `../scripts/lib/common.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/lib/common.sh`**

```sh
# scripts/lib/common.sh — paths, logging, and failure handling.
# Sourced by every entry point. Nothing here touches the filesystem except
# ad_repo_revision, which only reads.

ad_die()  { printf 'agent-dotfiles: %s\n' "$*" >&2; exit 1; }
ad_warn() { printf 'agent-dotfiles: %s\n' "$*" >&2; }
ad_say()  { printf '%s\n' "$*"; }

# Note: there is deliberately no ad_repo_root helper. Each entry point needs
# the repository root *before* it can source this file, so the three scripts
# inline `CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P` instead.

ad_claude_home()   { printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }
ad_opencode_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"; }
ad_state_home()    { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles"; }
ad_config_home()   { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/agent-dotfiles"; }

ad_timestamp() { date -u '+%Y-%m-%dT%H%M%SZ'; }

ad_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        ad_die "jq is required but not installed (brew install jq / apt install jq)"
    fi
}

ad_repo_revision() {
    if _r=$( cd "$1" 2>/dev/null && git rev-parse HEAD 2>/dev/null ); then
        printf '%s\n' "$_r"
    else
        printf 'unknown\n'
    fi
}
```

- [ ] **Step 4: Run to verify the path tests pass**

Run: `sh tests/run.sh`
Expected: all `test_common.sh` assertions ok.

- [ ] **Step 5: Write the failing tests for machine identity**

```sh
#!/bin/sh
# tests/test_machine.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/machine.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

assert_fail "load fails before any name is recorded" ad_machine_load
assert_ok   "valid name accepted" ad_machine_valid zephyrus-wsl
assert_fail "name with a slash rejected" ad_machine_valid "bad/name"
assert_fail "empty name rejected" ad_machine_valid ""

ad_machine_save macbook
assert_eq "load returns the saved name" "macbook" "$(ad_machine_load)"
assert_eq "resolve with no argument reads the saved name" "macbook" "$(ad_machine_resolve)"
assert_eq "resolve with an argument overrides" "thinkpad" "$(ad_machine_resolve thinkpad)"
assert_eq "an override persists for next time" "thinkpad" "$(ad_machine_load)"

sandbox_rm "$SB"
```

- [ ] **Step 6: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `machine.sh: No such file or directory`.

- [ ] **Step 7: Write `scripts/lib/machine.sh`**

```sh
# scripts/lib/machine.sh — which machine is this?
# The name is chosen by the user, not derived from the hostname, because
# hostnames are personal, unstable, and would be published.

ad_machine_file() { printf '%s\n' "$(ad_config_home)/machine"; }

ad_machine_valid() {
    case "${1:-}" in
        '')                  return 1 ;;
        *[!a-zA-Z0-9._-]*)   return 1 ;;
        *)                   return 0 ;;
    esac
}

ad_machine_save() {
    _f=$(ad_machine_file)
    mkdir -p "$(dirname -- "$_f")"
    printf '%s\n' "$1" > "$_f"
}

ad_machine_load() {
    _f=$(ad_machine_file)
    if [ ! -f "$_f" ]; then return 1; fi
    _n=$(cat "$_f")
    if [ -z "$_n" ]; then return 1; fi
    printf '%s\n' "$_n"
}

ad_machine_resolve() {
    if [ -n "${1:-}" ]; then
        if ! ad_machine_valid "$1"; then
            ad_die "invalid machine name '$1' (letters, digits, dot, dash, underscore only)"
        fi
        ad_machine_save "$1"
        printf '%s\n' "$1"
        return 0
    fi
    if ! ad_machine_load; then
        ad_die "no machine name recorded; pass --machine NAME on first run"
    fi
}
```

- [ ] **Step 8: Run to verify all pass**

Run: `sh tests/run.sh`
Expected: 0 failed.

- [ ] **Step 9: Commit**

```sh
git add scripts/lib/common.sh scripts/lib/machine.sh tests/test_common.sh tests/test_machine.sh
git commit -m "feat: add path accessors and machine identity resolution"
```

---

## Task 5: Target table

**Files:**
- Create: `scripts/lib/targets.sh`, `tests/test_targets.sh`

**Interfaces:**
- Consumes: `ad_claude_home`, `ad_opencode_home` from Task 4.
- Produces: `ad_targets_claude`, `ad_targets_opencode MACHINE`, and the row accessors `ad_row_kind ROW`, `ad_row_source ROW`, `ad_row_target ROW`. A row is `KIND|SOURCE_RELATIVE_TO_REPO|ABSOLUTE_TARGET`, where `KIND` is `dir`, `file`, or `gen`. Every consumer iterates rows; no other file hardcodes a path.

**Before writing:** if Task 2 Step 2 found that OpenCode's `instructions` glob resolves against the repository rather than the configuration directory, delete the `dir|shared|$_h/shared` row from `ad_targets_opencode` and note why in a comment.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
# tests/test_targets.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/targets.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

rows=$(ad_targets_claude)
assert_eq "claude table has 11 rows" "11" "$(printf '%s\n' "$rows" | grep -c .)"
assert_eq "shared is linked as claude rules" \
    "dir|shared|$SB/home/.claude/rules" \
    "$(printf '%s\n' "$rows" | grep '|rules$')"
assert_eq "settings is generated, not linked" \
    "gen" \
    "$(ad_row_kind "$(printf '%s\n' "$rows" | grep '/settings.json$')")"
assert_eq "plugins is never a claude target" "0" \
    "$(printf '%s\n' "$rows" | grep -c '/.claude/plugins$')"
assert_eq "projects is never a claude target" "0" \
    "$(printf '%s\n' "$rows" | grep -c '/.claude/projects$')"

orows=$(ad_targets_opencode thinkpad)
assert_eq "opencode table has 8 rows" "8" "$(printf '%s\n' "$orows" | grep -c .)"
assert_eq "machine file is linked to the fixed path" \
    "file|opencode/machines/thinkpad.json|$SB/home/.config/opencode/machine.json" \
    "$(printf '%s\n' "$orows" | grep '|machine.json$')"
assert_eq "node_modules is never an opencode target" "0" \
    "$(printf '%s\n' "$orows" | grep -c 'node_modules')"

row='dir|claude/skills|/tmp/x/skills'
assert_eq "row kind accessor"   "dir"          "$(ad_row_kind   "$row")"
assert_eq "row source accessor" "claude/skills" "$(ad_row_source "$row")"
assert_eq "row target accessor" "/tmp/x/skills" "$(ad_row_target "$row")"

sandbox_rm "$SB"
```

The two `grep -c` assertions for `plugins` and `projects` are regression guards: linking Claude Code's plugin cache or auto-memory directory would corrupt runtime state, so the table is tested for their *absence*, not just for what it contains.

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `targets.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/lib/targets.sh`**

```sh
# scripts/lib/targets.sh — the single declarative source of what gets linked.
#
# Row format: KIND|SOURCE_RELATIVE_TO_REPO|ABSOLUTE_TARGET
#   dir  - symlink a whole directory, so files added by a pull appear with no
#          install step. This is what makes "a pull is enough" true.
#   file - symlink one file.
#   gen  - generated by lib/settings.sh, never linked.
#
# Deliberately absent from the Claude table: plugins/, projects/, agent-memory/,
# sessions/, session-env/, history.jsonl, telemetry/, usage-data/,
# shell-snapshots/, file-history/, cache/, paste-cache/, tasks/, jobs/, daemon*,
# ide/, chrome/, plans/, backups/, stats-cache.json, .last-cleanup. These are
# runtime state written by Claude Code; linking them into a Git repository
# would corrupt them and publish session history.
#
# Deliberately absent from the OpenCode table: node_modules/, package.json,
# package-lock.json, bun.lock — plugin-loader output, generated in place.

ad_targets_claude() {
    _h=$(ad_claude_home)
    cat <<EOF
dir|shared|$_h/rules
dir|claude/agents|$_h/agents
dir|claude/commands|$_h/commands
dir|claude/skills|$_h/skills
dir|claude/workflows|$_h/workflows
dir|claude/output-styles|$_h/output-styles
dir|claude/themes|$_h/themes
file|claude/CLAUDE.md|$_h/CLAUDE.md
file|claude/keybindings.json|$_h/keybindings.json
file|claude/statusline.sh|$_h/statusline.sh
gen|claude/settings.json|$_h/settings.json
EOF
}

ad_targets_opencode() {
    _h=$(ad_opencode_home)
    _m=$1
    cat <<EOF
file|opencode/opencode.jsonc|$_h/opencode.jsonc
file|opencode/AGENTS.md|$_h/AGENTS.md
dir|opencode/agents|$_h/agents
dir|opencode/commands|$_h/commands
dir|opencode/skills|$_h/skills
dir|opencode/plugins|$_h/plugins
dir|shared|$_h/shared
file|opencode/machines/$_m.json|$_h/machine.json
EOF
}

ad_row_kind()   { printf '%s\n' "$1" | cut -d'|' -f1; }
ad_row_source() { printf '%s\n' "$1" | cut -d'|' -f2; }
ad_row_target() { printf '%s\n' "$1" | cut -d'|' -f3; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `sh tests/run.sh`
Expected: 0 failed.

- [ ] **Step 5: Commit**

```sh
git add scripts/lib/targets.sh tests/test_targets.sh
git commit -m "feat: add declarative link target table"
```

---

## Task 6: Backups and manifest

**Files:**
- Create: `scripts/lib/backup.sh`, `scripts/lib/manifest.sh`, `tests/test_backup.sh`, `tests/test_manifest.sh`

**Interfaces:**
- Consumes: `ad_state_home`, `ad_timestamp`, `ad_repo_revision` from Task 4.
- Produces: `ad_backup_dir TS`, `ad_backup_slot TS TARGET`, `ad_backup_move TS TARGET` (prints the slot), `ad_backup_restore SLOT TARGET`, `ad_backup_latest`; and `ad_manifest_path`, `ad_manifest_init REPO MACHINE`, `ad_manifest_add KIND SOURCE TARGET BACKUP`, `ad_manifest_targets` (prints `KIND|SOURCE|TARGET|BACKUP` rows), `ad_manifest_machine`.

- [ ] **Step 1: Write the failing backup test**

```sh
#!/bin/sh
# tests/test_backup.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/backup.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
TS=$(ad_timestamp)

mkdir -p "$HOME/.claude"
printf 'original\n' > "$HOME/.claude/CLAUDE.md"

slot=$(ad_backup_move "$TS" "$HOME/.claude/CLAUDE.md")
assert_file "backup slot exists" "$slot"
assert_eq "backup preserves content" "original" "$(cat "$slot")"
assert_fail "original is gone after the move" test -e "$HOME/.claude/CLAUDE.md"
case "$slot" in
    "$SB/home/.local/state/agent-dotfiles/backups/$TS"/*) _r=ok ;;
    *) _r="$slot" ;;
esac
assert_eq "backup lives under state home, not under .claude" "ok" "$_r"

ad_backup_restore "$slot" "$HOME/.claude/CLAUDE.md"
assert_eq "restore returns the original content" "original" "$(cat "$HOME/.claude/CLAUDE.md")"
assert_fail "restore refuses to clobber an existing target" \
    ad_backup_restore "$slot" "$HOME/.claude/CLAUDE.md"

assert_eq "latest backup is the timestamp we used" "$TS" "$(ad_backup_latest)"

sandbox_rm "$SB"
```

The "under state home, not under .claude" assertion encodes a spec decision: a backup directory inside `CLAUDE_HOME` would be read by Claude Code as live configuration.

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `backup.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/lib/backup.sh`**

```sh
# scripts/lib/backup.sh — move a conflicting target aside, reversibly.
#
# Backups live under the state home rather than inside either tool's
# configuration directory: a backup under CLAUDE_HOME would be read by Claude
# Code as live configuration.

ad_backup_dir() { printf '%s\n' "$(ad_state_home)/backups/$1"; }

# Slot path mirrors the absolute target path with the leading slash removed,
# so the original location is recoverable from the slot alone.
ad_backup_slot() {
    _rel=$(printf '%s' "$2" | sed 's|^/||')
    printf '%s\n' "$(ad_backup_dir "$1")/$_rel"
}

ad_backup_move() {
    _slot=$(ad_backup_slot "$1" "$2")
    mkdir -p "$(dirname -- "$_slot")"
    mv "$2" "$_slot"
    printf '%s\n' "$_slot"
}

ad_backup_restore() {
    if [ ! -e "$1" ]; then return 1; fi
    if [ -e "$2" ]; then return 1; fi
    mkdir -p "$(dirname -- "$2")"
    mv "$1" "$2"
}

ad_backup_latest() {
    _d="$(ad_state_home)/backups"
    if [ ! -d "$_d" ]; then return 1; fi
    _l=$(ls -1 "$_d" 2>/dev/null | sort | tail -1)
    if [ -z "$_l" ]; then return 1; fi
    printf '%s\n' "$_l"
}
```

- [ ] **Step 4: Run to verify backup tests pass**

Run: `sh tests/run.sh`
Expected: `test_backup.sh` all ok.

- [ ] **Step 5: Write the failing manifest test**

```sh
#!/bin/sh
# tests/test_manifest.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/manifest.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

ad_manifest_init "$SB/repo" macbook
assert_file "manifest created" "$(ad_manifest_path)"
assert_eq "machine recorded" "macbook" "$(ad_manifest_machine)"
assert_eq "revision of a non-repo is unknown" "unknown" \
    "$(jq -r .revision "$(ad_manifest_path)")"
assert_eq "targets start empty" "0" \
    "$(jq '.targets | length' "$(ad_manifest_path)")"

ad_manifest_add dir "$SB/repo/claude/skills" "$HOME/.claude/skills" ""
assert_eq "one target recorded" "1" "$(jq '.targets|length' "$(ad_manifest_path)")"
assert_eq "null backup when none taken" "null" \
    "$(jq -r '.targets[0].backup' "$(ad_manifest_path)")"

ad_manifest_add dir "$SB/repo/claude/skills" "$HOME/.claude/skills" "/some/slot"
assert_eq "re-adding the same target replaces rather than duplicates" "1" \
    "$(jq '.targets|length' "$(ad_manifest_path)")"
assert_eq "backup slot updated on replace" "/some/slot" \
    "$(jq -r '.targets[0].backup' "$(ad_manifest_path)")"

ad_manifest_add file "$SB/repo/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" ""
assert_eq "second distinct target appended" "2" "$(jq '.targets|length' "$(ad_manifest_path)")"
assert_eq "targets render as pipe rows" \
    "file|$SB/repo/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md|" \
    "$(ad_manifest_targets | grep 'CLAUDE.md')"

sandbox_rm "$SB"
```

The replace-not-duplicate assertion is what makes rerunning the installer idempotent at the manifest level, matching the spec's idempotence criterion.

- [ ] **Step 6: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `manifest.sh: No such file or directory`.

- [ ] **Step 7: Write `scripts/lib/manifest.sh`**

```sh
# scripts/lib/manifest.sh — the record of what this repository installed.
# uninstall.sh removes only what appears here and still matches.

ad_manifest_path() { printf '%s\n' "$(ad_state_home)/manifest.json"; }

ad_manifest_init() {
    _p=$(ad_manifest_path)
    mkdir -p "$(dirname -- "$_p")"
    jq -n --arg repo "$1" --arg machine "$2" \
          --arg rev "$(ad_repo_revision "$1")" --arg ts "$(ad_timestamp)" \
       '{repo: $repo, revision: $rev, machine: $machine,
         installed_at: $ts, targets: []}' > "$_p"
}

ad_manifest_machine() {
    _p=$(ad_manifest_path)
    if [ ! -f "$_p" ]; then return 1; fi
    jq -r '.machine' "$_p"
}

# Replaces any existing row for the same target, so reruns do not duplicate.
ad_manifest_add() {
    _p=$(ad_manifest_path)
    jq --arg kind "$1" --arg src "$2" --arg tgt "$3" --arg bak "$4" \
       --arg ts "$(ad_timestamp)" \
       '.targets |= (map(select(.target != $tgt))
                     + [{kind: $kind, source: $src, target: $tgt,
                         backup: (if $bak == "" then null else $bak end),
                         timestamp: $ts}])' "$_p" > "$_p.tmp"
    mv "$_p.tmp" "$_p"
}

ad_manifest_targets() {
    _p=$(ad_manifest_path)
    if [ ! -f "$_p" ]; then return 1; fi
    jq -r '.targets[] | [.kind, .source, .target, (.backup // "")] | join("|")' "$_p"
}
```

- [ ] **Step 8: Run to verify all pass**

Run: `sh tests/run.sh`
Expected: 0 failed.

- [ ] **Step 9: Commit**

```sh
git add scripts/lib/backup.sh scripts/lib/manifest.sh tests/test_backup.sh tests/test_manifest.sh
git commit -m "feat: add reversible backups and install manifest"
```

---

## Task 7: Link rules

**Files:**
- Create: `scripts/lib/link.sh`, `tests/test_link.sh`

**Interfaces:**
- Consumes: `ad_backup_move`, `ad_backup_slot` from Task 6.
- Produces: `ad_link_state TARGET SOURCE` printing one of `missing`, `ok`, `foreign`, `occupied`; and `ad_link_apply SOURCE TARGET FORCE DRY TIMESTAMP` printing `create` / `noop` / `replace SLOT` / `refuse REASON` / `missing-source` with exit codes `0` success, `3` refused, `4` source missing.

**Caller contract:** `ad_link_apply` returns non-zero for refusal, so under `set -e` a caller must write `out=$(ad_link_apply ...) || rc=$?` and never call it bare.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
# tests/test_link.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/backup.sh
. ../scripts/lib/link.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
TS=$(ad_timestamp)
SRC="$SB/repo/claude/skills"
TGT="$HOME/.claude/skills"
mkdir -p "$SRC" "$HOME/.claude"

# state detection
assert_eq "missing target" "missing" "$(ad_link_state "$TGT" "$SRC")"

# rule 1: create when missing
out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS")
assert_eq "creates the link" "create" "$out"
assert_link "link points at the repo" "$TGT" "$SRC"
assert_eq "correct link reads as ok" "ok" "$(ad_link_state "$TGT" "$SRC")"

# rule 2: idempotent no-op
out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS")
assert_eq "rerun is a no-op" "noop" "$out"
assert_eq "no backup was created on a no-op run" "0" \
    "$(ls -1 "$(ad_state_home)/backups" 2>/dev/null | wc -l | tr -d ' ')"

# rule 3a: refuse a foreign link
rm "$TGT"; ln -s "$SB/elsewhere" "$TGT"
assert_eq "foreign link detected" "foreign" "$(ad_link_state "$TGT" "$SRC")"
rc=0; out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS") || rc=$?
assert_eq "foreign link refused" "3" "$rc"
assert_eq "refusal names the reason" "refuse foreign" "$out"
assert_link "refusal left the foreign link intact" "$TGT" "$SB/elsewhere"

# rule 3b: refuse real content
rm "$TGT"; mkdir -p "$TGT/impeccable"; printf 'x\n' > "$TGT/impeccable/SKILL.md"
assert_eq "real directory detected" "occupied" "$(ad_link_state "$TGT" "$SRC")"
rc=0; out=$(ad_link_apply "$SRC" "$TGT" 0 0 "$TS") || rc=$?
assert_eq "real directory refused without --force" "3" "$rc"
assert_file "refusal left the real content intact" "$TGT/impeccable/SKILL.md"

# --force backs up, then links
out=$(ad_link_apply "$SRC" "$TGT" 1 0 "$TS")
assert_link "force replaced with our link" "$TGT" "$SRC"
slot=$(printf '%s' "$out" | cut -d' ' -f2)
assert_file "displaced content preserved in the backup" "$slot/impeccable/SKILL.md"

# --dry-run changes nothing
rm "$TGT"
out=$(ad_link_apply "$SRC" "$TGT" 0 1 "$TS")
assert_eq "dry run reports the create" "create" "$out"
assert_fail "dry run did not create the link" test -e "$TGT"

# missing source is skipped, not fatal
rc=0; out=$(ad_link_apply "$SB/nope" "$HOME/.claude/nope" 0 0 "$TS") || rc=$?
assert_eq "missing source exits 4" "4" "$rc"
assert_eq "missing source reports itself" "missing-source" "$out"

sandbox_rm "$SB"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `link.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/lib/link.sh`**

```sh
# scripts/lib/link.sh — the three link rules.
#
#   1. target missing            -> create the link
#   2. target already correct    -> no operation (this is what makes reruns
#                                   idempotent: no backup, no rewrite)
#   3. anything else             -> refuse, unless --force, which backs up first
#
# Refusing by default is deliberate. Hand migration was chosen over automatic
# adoption, so the installer must never silently absorb or discard content it
# did not create.

ad_link_state() {
    if [ -L "$1" ]; then
        if [ "$(readlink "$1")" = "$2" ]; then printf 'ok\n'; else printf 'foreign\n'; fi
    elif [ -e "$1" ]; then
        printf 'occupied\n'
    else
        printf 'missing\n'
    fi
}

# $1 source  $2 target  $3 force(0|1)  $4 dry(0|1)  $5 timestamp
# exit 0 applied, 3 refused, 4 source missing
ad_link_apply() {
    if [ ! -e "$1" ]; then
        printf 'missing-source\n'
        return 4
    fi

    _st=$(ad_link_state "$2" "$1")

    if [ "$_st" = "ok" ]; then
        printf 'noop\n'
        return 0
    fi

    if [ "$_st" = "missing" ]; then
        if [ "$4" -eq 0 ]; then
            mkdir -p "$(dirname -- "$2")"
            ln -s "$1" "$2"
        fi
        printf 'create\n'
        return 0
    fi

    if [ "$3" -ne 1 ]; then
        printf 'refuse %s\n' "$_st"
        return 3
    fi

    if [ "$4" -eq 1 ]; then
        printf 'replace %s\n' "$(ad_backup_slot "$5" "$2")"
        return 0
    fi

    _slot=$(ad_backup_move "$5" "$2")
    mkdir -p "$(dirname -- "$2")"
    ln -s "$1" "$2"
    printf 'replace %s\n' "$_slot"
    return 0
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `sh tests/run.sh`
Expected: 0 failed.

- [ ] **Step 5: Commit**

```sh
git add scripts/lib/link.sh tests/test_link.sh
git commit -m "feat: add link rules with refusal, backup, and idempotent reruns"
```

---

## Task 8: Settings generation

**Files:**
- Create: `scripts/lib/settings.sh`, `tests/test_settings.sh`

**Interfaces:**
- Consumes: `ad_die` from Task 4, `jq`.
- Produces: `ad_settings_merge LIVE BASE MACHINE` printing merged JSON to stdout; `ad_settings_write REPO MACHINE TARGET CLEAN DRY`.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
# tests/test_settings.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/settings.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
mkdir -p "$SB/repo/claude/machines" "$HOME/.claude"
LIVE="$HOME/.claude/settings.json"
BASE="$SB/repo/claude/settings.json"
MACH="$SB/repo/claude/machines/macbook.json"

# The live file carries what Claude Code wrote for itself, including the
# private auto-mode block that must never enter the repository.
cat > "$LIVE" <<'EOF'
{"theme":"dark","autoMode":{"environment":["/Users/souvik/private/repo"]},
 "permissions":{"allow":["Bash(ls:*)"]}}
EOF
cat > "$BASE" <<'EOF'
{"model":"opus","permissions":{"allow":["Bash(git:*)"],"deny":["Bash(rm:*)"]}}
EOF
printf '{"model":"sonnet"}\n' > "$MACH"

out=$(ad_settings_merge "$LIVE" "$BASE" "$MACH")

assert_eq "machine layer beats base" "sonnet" "$(printf '%s' "$out" | jq -r .model)"
assert_eq "live-only key survives regeneration" "dark" "$(printf '%s' "$out" | jq -r .theme)"
assert_eq "private auto-mode block survives and is untouched" \
    "/Users/souvik/private/repo" \
    "$(printf '%s' "$out" | jq -r '.autoMode.environment[0]')"
assert_eq "objects merge recursively: base deny is added" "Bash(rm:*)" \
    "$(printf '%s' "$out" | jq -r '.permissions.deny[0]')"
assert_eq "arrays replace rather than concatenate" "Bash(git:*)" \
    "$(printf '%s' "$out" | jq -r '.permissions.allow[0]')"
assert_eq "arrays replace: length is base's, not the sum" "1" \
    "$(printf '%s' "$out" | jq '.permissions.allow | length')"

# absent layers degrade to empty objects rather than failing
out2=$(ad_settings_merge /nonexistent "$BASE" /nonexistent)
assert_eq "absent live and machine layers are tolerated" "opus" \
    "$(printf '%s' "$out2" | jq -r .model)"

# --clean drops the live layer entirely
ad_settings_write "$SB/repo" macbook "$LIVE" 1 0
assert_eq "clean regeneration drops live-only keys" "null" \
    "$(jq -r '.theme' "$LIVE")"
assert_eq "clean regeneration keeps repository keys" "sonnet" "$(jq -r .model "$LIVE")"

# dry run writes nothing
printf '{"marker":"untouched"}\n' > "$LIVE"
ad_settings_write "$SB/repo" macbook "$LIVE" 0 1
assert_eq "dry run leaves the file untouched" "untouched" "$(jq -r .marker "$LIVE")"

sandbox_rm "$SB"
```

The auto-mode assertion is the security property from the spec expressed as a test: that block must round-trip through regeneration and must never be sourced from the repository.

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `settings.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/lib/settings.sh`**

```sh
# scripts/lib/settings.sh — generate Claude Code's user settings file.
#
# Claude Code has exactly one user-scope settings file and no user-level
# override, and it writes to that file itself (/config changes, and auto mode's
# environment block, which holds private repository paths). Symlinking it into a
# public repository would publish those writes continuously, so the file is
# generated instead.
#
# Three-way deep merge, lowest precedence first:
#   1. the live file on disk   - keys we do not define survive, and never enter Git
#   2. claude/settings.json    - shared base
#   3. claude/machines/<name>.json - this machine
#
# Objects merge recursively; every non-object value, arrays included, is
# replaced by the higher layer.

ad_settings_merge() {
    _l=$1; _b=$2; _m=$3
    if [ ! -f "$_l" ]; then _l=/dev/null; fi
    if [ ! -f "$_b" ]; then _b=/dev/null; fi
    if [ ! -f "$_m" ]; then _m=/dev/null; fi
    jq -n --slurpfile live "$_l" --slurpfile base "$_b" --slurpfile machine "$_m" '
      def deepmerge(b):
        reduce (b | keys_unsorted[]) as $k (.;
          if (.[$k] | type) == "object" and (b[$k] | type) == "object"
          then .[$k] |= deepmerge(b[$k])
          else .[$k] = b[$k]
          end
        );
      ($live[0] // {}) | deepmerge($base[0] // {}) | deepmerge($machine[0] // {})
    '
}

# $1 repo  $2 machine  $3 target  $4 clean(0|1)  $5 dry(0|1)
ad_settings_write() {
    _live=$3
    if [ "$4" -eq 1 ]; then _live=/dev/null; fi
    if ! _out=$(ad_settings_merge "$_live" \
                                  "$1/claude/settings.json" \
                                  "$1/claude/machines/$2.json" 2>&1); then
        ad_die "settings merge failed (is $3 valid JSON?): $_out"
    fi
    # Dry run still performs the merge, so a malformed layer surfaces, but
    # writes nothing and prints nothing.
    if [ "$5" -eq 1 ]; then return 0; fi
    mkdir -p "$(dirname -- "$3")"
    printf '%s\n' "$_out" > "$3.tmp"
    mv "$3.tmp" "$3"
}
```

`--slurpfile` on `/dev/null` yields an empty array, so `$live[0] // {}` gives `{}` — that is how a missing layer degrades instead of failing.

- [ ] **Step 4: Run to verify it passes**

Run: `sh tests/run.sh`
Expected: 0 failed.

- [ ] **Step 5: Commit**

```sh
git add scripts/lib/settings.sh tests/test_settings.sh
git commit -m "feat: generate claude settings by three-way deep merge"
```

---

## Task 9: install.sh

**Files:**
- Create: `scripts/install.sh`, `tests/test_install.sh`

**Interfaces:**
- Consumes: every library from Tasks 4-8.
- Produces: the installer entry point. Exit codes: `0` success, `1` usage or fatal error, `3` one or more targets refused.

- [ ] **Step 1: Write the failing end-to-end test**

```sh
#!/bin/sh
# tests/test_install.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
INSTALL="$REPO/scripts/install.sh"

assert_ok "--help works and exits 0" sh "$INSTALL" --help
assert_fail "no component flag is a usage error" sh "$INSTALL" --machine macbook
assert_fail "no machine on first run is an error" sh "$INSTALL" --all

# dry run changes nothing
sh "$INSTALL" --all --machine macbook --dry-run >/dev/null
assert_fail "dry run created no claude dir" test -e "$HOME/.claude/skills"
assert_fail "dry run wrote no manifest" test -e "$(ad_state_home)/manifest.json"
assert_fail "dry run recorded no machine name" test -e "$(ad_config_home)/machine"

# real install
sh "$INSTALL" --all --machine macbook >/dev/null
assert_link "skills linked" "$HOME/.claude/skills" "$REPO/claude/skills"
assert_link "rules linked to shared" "$HOME/.claude/rules" "$REPO/shared"
assert_link "opencode machine.json linked" \
    "$HOME/.config/opencode/machine.json" "$REPO/opencode/machines/macbook.json"
assert_file "settings generated" "$HOME/.claude/settings.json"
assert_fail "settings is a real file, not a link" test -L "$HOME/.claude/settings.json"
assert_fail "plugins never linked" test -L "$HOME/.claude/plugins"
assert_file "manifest written" "$(ad_state_home)/manifest.json"
assert_eq "machine recorded" "macbook" "$(cat "$(ad_config_home)/machine")"

# idempotence
before=$(ls -1 "$(ad_state_home)/backups" 2>/dev/null | wc -l | tr -d ' ')
sh "$INSTALL" --all >/dev/null
after=$(ls -1 "$(ad_state_home)/backups" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "rerun creates no new backup" "$before" "$after"
assert_eq "rerun needs no --machine" "macbook" "$(cat "$(ad_config_home)/machine")"
assert_link "rerun left the link alone" "$HOME/.claude/skills" "$REPO/claude/skills"

# conflict refusal
rm "$HOME/.claude/skills"; mkdir -p "$HOME/.claude/skills/mine"
rc=0; sh "$INSTALL" --claude >/dev/null 2>&1 || rc=$?
assert_eq "conflict exits 3" "3" "$rc"
assert_file "conflicting content untouched" "$HOME/.claude/skills/mine"

# --force backs up and replaces
sh "$INSTALL" --claude --force >/dev/null
assert_link "force replaced the conflict" "$HOME/.claude/skills" "$REPO/claude/skills"
assert_eq "exactly one backup generation exists" "1" \
    "$(ls -1 "$(ad_state_home)/backups" | wc -l | tr -d ' ')"

# component selectivity
sandbox_rm "$SB"; SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
sh "$INSTALL" --claude --machine thinkpad >/dev/null
assert_file "claude-only install touched claude" "$HOME/.claude/skills"
assert_fail "claude-only install did not touch opencode" test -e "$HOME/.config/opencode/agents"

sandbox_rm "$SB"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `install.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/install.sh`**

```sh
#!/bin/sh
# install.sh — link this repository into OpenCode's and Claude Code's global
# configuration directories.
#
# Never makes a network request, installs a package, or edits a shell startup
# file. Repository root is derived from this script's own resolved path.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/machine.sh"
. "$AD_ROOT/scripts/lib/targets.sh"
. "$AD_ROOT/scripts/lib/backup.sh"
. "$AD_ROOT/scripts/lib/manifest.sh"
. "$AD_ROOT/scripts/lib/link.sh"
. "$AD_ROOT/scripts/lib/settings.sh"

usage() {
    cat <<'EOF'
Usage: install.sh (--claude | --opencode | --all) [options]

Components (at least one required):
  --claude          link Claude Code files and generate its settings
  --opencode        link OpenCode files
  --all             both

Options:
  --machine NAME    name this machine; required on first run, remembered after
  --dry-run         print every planned operation, change nothing
  --force           back up and replace a conflicting target
  --clean           regenerate settings.json from repository layers only,
                    discarding keys that exist solely in the live file
  --hook            install a git post-merge hook so a pull re-runs this script
  --help            this message

Safety:
  A target that is a real file, a real directory, or a symlink owned by
  something else is REFUSED, not overwritten. Use --force to back it up under
  $XDG_STATE_HOME/agent-dotfiles/backups and replace it. Rerunning with no
  changes creates no backups and rewrites nothing.

Exit codes: 0 ok, 1 usage or fatal error, 3 one or more targets refused.
EOF
}

do_claude=0; do_opencode=0; force=0; dry=0; clean=0; hook=0; machine=''
while [ $# -gt 0 ]; do
    case $1 in
        --claude)     do_claude=1 ;;
        --opencode)   do_opencode=1 ;;
        --all)        do_claude=1; do_opencode=1 ;;
        --machine)    shift; machine=${1:-} ;;
        --machine=*)  machine=${1#--machine=} ;;
        --dry-run)    dry=1 ;;
        --force)      force=1 ;;
        --clean)      clean=1 ;;
        --hook)       hook=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            usage >&2; ad_die "unknown option: $1" ;;
    esac
    shift
done

if [ "$do_claude" -eq 0 ] && [ "$do_opencode" -eq 0 ]; then
    usage >&2
    ad_die "choose --claude, --opencode, or --all"
fi

ad_require_jq

# A dry run must change nothing at all, including the recorded machine name,
# so validate the given name rather than saving it.
if [ "$dry" -eq 1 ] && [ -n "$machine" ]; then
    if ! ad_machine_valid "$machine"; then
        ad_die "invalid machine name '$machine'"
    fi
else
    machine=$(ad_machine_resolve "$machine")
fi
ts=$(ad_timestamp)

if [ "$dry" -eq 1 ]; then ad_say "dry run — nothing will change"; fi
ad_say "machine: $machine"
ad_say "repo:    $AD_ROOT"

if [ "$dry" -eq 0 ]; then ad_manifest_init "$AD_ROOT" "$machine"; fi

rowfile=$(mktemp "${TMPDIR:-/tmp}/agent-dotfiles-rows.XXXXXX")
trap 'rm -f "$rowfile"' EXIT INT TERM
{
    if [ "$do_claude" -eq 1 ];   then ad_targets_claude; fi
    if [ "$do_opencode" -eq 1 ]; then ad_targets_opencode "$machine"; fi
} > "$rowfile"

refused=0
# Read from a file, not a pipe: a pipeline would run this loop in a subshell
# and the refusal counter would be lost.
while IFS= read -r row; do
    kind=$(ad_row_kind "$row")
    src="$AD_ROOT/$(ad_row_source "$row")"
    tgt=$(ad_row_target "$row")

    if [ "$kind" = "gen" ]; then
        ad_settings_write "$AD_ROOT" "$machine" "$tgt" "$clean" "$dry"
        ad_say "  generate  $tgt"
        if [ "$dry" -eq 0 ]; then ad_manifest_add gen "$src" "$tgt" ""; fi
        continue
    fi

    rc=0
    out=$(ad_link_apply "$src" "$tgt" "$force" "$dry" "$ts") || rc=$?
    action=$(printf '%s' "$out" | cut -d' ' -f1)
    detail=$(printf '%s' "$out" | cut -s -d' ' -f2)

    case $rc in
        0)  ad_say "  $action    $tgt"
            if [ "$dry" -eq 0 ]; then ad_manifest_add "$kind" "$src" "$tgt" "$detail"; fi ;;
        3)  refused=$((refused + 1))
            ad_warn "  refuse    $tgt ($detail) — rerun with --force to back it up and replace it" ;;
        4)  ad_warn "  skip      $tgt (source missing: $src)" ;;
        *)  ad_die "unexpected failure linking $tgt" ;;
    esac
done < "$rowfile"

if [ "$hook" -eq 1 ] && [ "$dry" -eq 0 ]; then
    if [ -d "$AD_ROOT/.git" ]; then
        cat > "$AD_ROOT/.git/hooks/post-merge" <<'HOOK'
#!/bin/sh
# Installed by agent-dotfiles install.sh --hook.
# Regenerates settings after a pull, so `git pull` is the whole update workflow.
exec "$(git rev-parse --show-toplevel)/scripts/install.sh" --all
HOOK
        chmod +x "$AD_ROOT/.git/hooks/post-merge"
        ad_say "installed post-merge hook: git pull now re-runs this installer"
    else
        ad_warn "not a git clone; skipped --hook"
    fi
fi

cat <<EOF

Add these two lines to your shell startup file if they are not there already.
They are identical on every machine, and this installer will not edit the file
for you:

  [ -f "\$HOME/.config/agent-dotfiles/env" ] && . "\$HOME/.config/agent-dotfiles/env"
  export OPENCODE_CONFIG="\$HOME/.config/opencode/machine.json"
EOF

if [ "$refused" -gt 0 ]; then
    ad_warn ""
    ad_warn "$refused target(s) refused. Nothing was overwritten."
    exit 3
fi
```

- [ ] **Step 4: Run to verify it passes**

```sh
chmod +x scripts/install.sh
sh tests/run.sh
```
Expected: 0 failed.

- [ ] **Step 5: Commit**

```sh
git add scripts/install.sh tests/test_install.sh
git commit -m "feat: add installer with dry-run, refusal, force, and post-merge hook"
```

---

## Task 10: uninstall.sh

**Files:**
- Create: `scripts/uninstall.sh`, `tests/test_uninstall.sh`

**Interfaces:**
- Consumes: `ad_manifest_targets`, `ad_link_state`, `ad_backup_restore`, `ad_backup_latest`.
- Produces: the uninstall entry point. Exit codes: `0` success, `1` fatal, `3` one or more targets refused.

**Design note on the generated settings file:** it was merged, never backed up, and now contains Claude Code's own writes. Removing it would destroy those. `uninstall.sh` therefore leaves it in place and says so, unless `--force`.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
# tests/test_uninstall.sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
INSTALL="$REPO/scripts/install.sh"
UNINSTALL="$REPO/scripts/uninstall.sh"

assert_ok "--help works" sh "$UNINSTALL" --help
assert_fail "uninstall without a manifest fails cleanly" sh "$UNINSTALL"

sh "$INSTALL" --all --machine macbook >/dev/null

# dry run removes nothing
sh "$UNINSTALL" --dry-run >/dev/null
assert_link "dry run left the link" "$HOME/.claude/skills" "$REPO/claude/skills"

# a drifted target is refused
rm "$HOME/.claude/agents"; ln -s "$SB/elsewhere" "$HOME/.claude/agents"
rc=0; sh "$UNINSTALL" >/dev/null 2>&1 || rc=$?
assert_eq "drift causes exit 3" "3" "$rc"
assert_link "drifted target left alone" "$HOME/.claude/agents" "$SB/elsewhere"
assert_fail "matching targets still removed alongside the refusal" \
    test -L "$HOME/.claude/skills"

# generated settings survive by default
assert_file "generated settings not removed by default" "$HOME/.claude/settings.json"

# --force removes drifted targets and the generated file
sh "$UNINSTALL" --force >/dev/null
assert_fail "force removed the drifted target" test -e "$HOME/.claude/agents"
assert_fail "force removed the generated settings" test -e "$HOME/.claude/settings.json"

# --restore puts a backup back
sandbox_rm "$SB"; SB=$(sandbox_new); eval "$(sandbox_env "$SB")"
mkdir -p "$HOME/.claude/skills/mine"; printf 'original\n' > "$HOME/.claude/skills/mine/SKILL.md"
sh "$INSTALL" --claude --machine macbook --force >/dev/null
sh "$UNINSTALL" --restore >/dev/null
assert_file "restore returned the displaced content" "$HOME/.claude/skills/mine/SKILL.md"
assert_eq "restored content is intact" "original" "$(cat "$HOME/.claude/skills/mine/SKILL.md")"
assert_fail "restored path is no longer our link" test -L "$HOME/.claude/skills"

sandbox_rm "$SB"
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `uninstall.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/uninstall.sh`**

```sh
#!/bin/sh
# uninstall.sh — remove only what this repository installed, and only when the
# target still matches the manifest.
set -eu

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/backup.sh"
. "$AD_ROOT/scripts/lib/manifest.sh"
. "$AD_ROOT/scripts/lib/link.sh"

usage() {
    cat <<'EOF'
Usage: uninstall.sh [options]

  --dry-run   print what would be removed, change nothing
  --force     remove targets that no longer match the manifest, and remove the
              generated settings.json
  --restore   after removing, move backed-up originals back into place
  --help      this message

Removes only targets recorded in the manifest whose current state still matches
it. A target someone else has changed is refused, so an unrelated file is never
deleted. The generated settings.json is kept by default: it holds settings
Claude Code wrote for itself that exist nowhere else.

Exit codes: 0 ok, 1 fatal, 3 one or more targets refused.
EOF
}

dry=0; force=0; restore=0
while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) dry=1 ;;
        --force)   force=1 ;;
        --restore) restore=1 ;;
        -h|--help) usage; exit 0 ;;
        *)         usage >&2; ad_die "unknown option: $1" ;;
    esac
    shift
done

ad_require_jq
if [ ! -f "$(ad_manifest_path)" ]; then
    ad_die "no manifest at $(ad_manifest_path); nothing was installed by this repository"
fi

rowfile=$(mktemp "${TMPDIR:-/tmp}/agent-dotfiles-un.XXXXXX")
trap 'rm -f "$rowfile"' EXIT INT TERM
ad_manifest_targets > "$rowfile"

refused=0
while IFS='|' read -r kind src tgt bak; do
    if [ -z "${tgt:-}" ]; then continue; fi

    if [ "$kind" = "gen" ]; then
        if [ "$force" -eq 1 ]; then
            if [ "$dry" -eq 0 ]; then rm -f "$tgt"; fi
            ad_say "  remove    $tgt (generated)"
        else
            ad_say "  keep      $tgt (generated; holds settings Claude Code wrote — use --force to remove)"
        fi
        continue
    fi

    state=$(ad_link_state "$tgt" "$src")
    case $state in
        ok)
            if [ "$dry" -eq 0 ]; then rm -f "$tgt"; fi
            ad_say "  remove    $tgt" ;;
        missing)
            ad_say "  absent    $tgt" ;;
        *)
            if [ "$force" -eq 1 ]; then
                if [ "$dry" -eq 0 ]; then rm -rf "$tgt"; fi
                ad_say "  remove    $tgt (forced, was $state)"
            else
                refused=$((refused + 1))
                ad_warn "  refuse    $tgt (is $state, not ours) — use --force to remove it anyway"
            fi ;;
    esac

    if [ "$restore" -eq 1 ] && [ -n "${bak:-}" ] && [ "$dry" -eq 0 ]; then
        if ad_backup_restore "$bak" "$tgt"; then
            ad_say "  restore   $tgt"
        else
            ad_warn "  restore failed for $tgt (backup missing, or target still present)"
        fi
    fi
done < "$rowfile"

if [ "$refused" -gt 0 ]; then
    ad_warn ""
    ad_warn "$refused target(s) refused. Nothing unrelated was deleted."
    exit 3
fi
```

- [ ] **Step 4: Run to verify it passes**

```sh
chmod +x scripts/uninstall.sh
sh tests/run.sh
```
Expected: 0 failed.

- [ ] **Step 5: Commit**

```sh
git add scripts/uninstall.sh tests/test_uninstall.sh
git commit -m "feat: add uninstall with drift refusal and backup restore"
```

---

## Task 11: validate.sh and CI

**Files:**
- Create: `scripts/validate.sh`, `tests/test_validate.sh`, `.github/workflows/validate.yml`

**Interfaces:**
- Consumes: `ad_settings_merge` from Task 8; the library path accessors.
- Produces: `scripts/validate.sh`, exit `0` clean / `1` at least one check failed. It must never write outside a temp file.

**Constraint discovered while planning:** the repository's `opencode.jsonc` must be strict-JSON parseable. OpenCode permits comments, but stripping `//` comments correctly in POSIX shell is not worth the fragility — a naive stripper corrupts `"https://opencode.ai/config.json"`. The file keeps its `.jsonc` extension for OpenCode's benefit and carries a header comment saying comments are not used. Note this in the file.

**Secret-scan scope:** only installed content is scanned — `shared/`, `opencode/`, `claude/`, `scripts/`, `README.md`. `docs/` and `tests/` are excluded by design, because the spec, this plan, and `tests/test_settings.sh` all legitimately quote a private path as example data.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
# tests/test_validate.sh
set -u
. ./helpers.sh
. ./sandbox.sh

REPO=$(CDPATH= cd -- .. && pwd -P)
V="$REPO/scripts/validate.sh"

assert_ok "the repository validates as shipped" sh "$V"

SB=$(sandbox_new)
cp -R "$REPO" "$SB/clone"
rm -rf "$SB/clone/.git"

printf '{"model": }\n' > "$SB/clone/claude/settings.json"
assert_fail "malformed settings.json fails validation" sh "$SB/clone/scripts/validate.sh"
printf '{}\n' > "$SB/clone/claude/settings.json"

printf '{"model": }\n' > "$SB/clone/claude/machines/thinkpad.json"
assert_fail "a malformed machine file fails even when it is not this machine" \
    sh "$SB/clone/scripts/validate.sh"
printf '{}\n' > "$SB/clone/claude/machines/thinkpad.json"

printf -- '---\nname: broken\n' > "$SB/clone/claude/skills/broken.md"
assert_fail "unterminated frontmatter fails validation" sh "$SB/clone/scripts/validate.sh"
rm "$SB/clone/claude/skills/broken.md"

printf 'export TOKEN=/Users/someone/secret\n' > "$SB/clone/shared/leak.md"
assert_fail "an absolute home path in installed content fails validation" \
    sh "$SB/clone/scripts/validate.sh"
rm "$SB/clone/shared/leak.md"

assert_ok "clone validates again once the faults are removed" sh "$SB/clone/scripts/validate.sh"

sandbox_rm "$SB"
```

The `thinkpad.json` case matters: a machine file broken on the MacBook must fail there, or the breakage only surfaces after it has been pulled onto the ThinkPad.

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/run.sh`
Expected: FAIL — `validate.sh: No such file or directory`.

- [ ] **Step 3: Write `scripts/validate.sh`**

```sh
#!/bin/sh
# validate.sh — check the repository without touching the home directory.
set -u

AD_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$AD_ROOT/scripts/lib/common.sh"
. "$AD_ROOT/scripts/lib/settings.sh"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# --- dependencies -----------------------------------------------------------
if command -v jq >/dev/null 2>&1; then ok "jq present"
else bad "jq missing (brew install jq / apt install jq)"; fi

# --- JSON parses ------------------------------------------------------------
# opencode.jsonc must be strict JSON: OpenCode allows comments, but this
# repository does not use them so validation needs no JSONC parser.
for f in "$AD_ROOT/claude/settings.json" \
         "$AD_ROOT/claude/keybindings.json" \
         "$AD_ROOT/opencode/opencode.jsonc" \
         "$AD_ROOT"/claude/machines/*.json \
         "$AD_ROOT"/opencode/machines/*.json; do
    if [ ! -f "$f" ]; then continue; fi
    if jq empty "$f" >/dev/null 2>&1; then ok "parses: ${f#"$AD_ROOT"/}"
    else bad "invalid JSON: ${f#"$AD_ROOT"/}"; fi
done

# --- every machine's merge, not just this one -------------------------------
for f in "$AD_ROOT"/claude/machines/*.json; do
    if [ ! -f "$f" ]; then continue; fi
    m=$(basename "$f" .json)
    if ad_settings_merge /dev/null "$AD_ROOT/claude/settings.json" "$f" >/dev/null 2>&1
    then ok "settings merge for machine: $m"
    else bad "settings merge fails for machine: $m"; fi
done

# --- markdown frontmatter ---------------------------------------------------
for f in $(find "$AD_ROOT/claude" "$AD_ROOT/opencode" "$AD_ROOT/shared" \
             -name '*.md' -type f 2>/dev/null); do
    if [ "$(head -1 "$f")" != "---" ]; then continue; fi
    if [ "$(sed -n '2,$p' "$f" | grep -c '^---$')" -ge 1 ]; then
        ok "frontmatter closed: ${f#"$AD_ROOT"/}"
    else
        bad "unterminated frontmatter: ${f#"$AD_ROOT"/}"
    fi
done

# --- referenced paths resolve ----------------------------------------------
if [ -f "$AD_ROOT/claude/statusline.sh" ]; then
    if [ -x "$AD_ROOT/claude/statusline.sh" ]; then ok "statusline.sh is executable"
    else bad "statusline.sh is not executable (chmod +x)"; fi
fi
if jq -e '.instructions' "$AD_ROOT/opencode/opencode.jsonc" >/dev/null 2>&1; then
    ok "opencode declares instructions"
else
    bad "opencode.jsonc has no instructions key; shared/ would not be loaded"
fi

# --- shell syntax -----------------------------------------------------------
for f in "$AD_ROOT"/scripts/*.sh "$AD_ROOT"/scripts/lib/*.sh "$AD_ROOT"/tests/*.sh; do
    if [ ! -f "$f" ]; then continue; fi
    if sh -n "$f" 2>/dev/null; then ok "syntax: ${f#"$AD_ROOT"/}"
    else bad "syntax error: ${f#"$AD_ROOT"/}"; fi
done
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s sh "$AD_ROOT"/scripts/*.sh "$AD_ROOT"/scripts/lib/*.sh >/dev/null 2>&1
    then ok "shellcheck clean"
    else bad "shellcheck reported problems (run: shellcheck -s sh scripts/*.sh scripts/lib/*.sh)"; fi
else
    printf '  warn shellcheck not installed; CI will run it\n'
fi

# --- no private paths or secrets in installed content -----------------------
# docs/ and tests/ are excluded: the spec, the plan, and the settings tests all
# legitimately quote a private path as example data.
scan=$(find "$AD_ROOT/shared" "$AD_ROOT/opencode" "$AD_ROOT/claude" \
            "$AD_ROOT/scripts" -type f 2>/dev/null)
if [ -f "$AD_ROOT/README.md" ]; then scan="$scan
$AD_ROOT/README.md"; fi
hits=0
for f in $scan; do
    if grep -qE '(/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+)' "$f" 2>/dev/null; then
        bad "absolute home path in ${f#"$AD_ROOT"/}"; hits=1
    fi
    if grep -qE '(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|BEGIN [A-Z ]*PRIVATE KEY)' "$f" 2>/dev/null; then
        bad "possible secret in ${f#"$AD_ROOT"/}"; hits=1
    fi
done
if [ "$hits" -eq 0 ]; then ok "no private paths or secret patterns in installed content"; fi

printf '\n%s check(s) failed\n' "$fails"
[ "$fails" -eq 0 ]
```

- [ ] **Step 4: Run to verify it passes**

```sh
chmod +x scripts/validate.sh
sh scripts/validate.sh
sh tests/run.sh
```
Expected: both exit 0.

- [ ] **Step 5: Write the CI workflow**

```yaml
# .github/workflows/validate.yml
name: validate
on:
  push:
    branches: [main]
  pull_request:

jobs:
  validate:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Install jq and shellcheck (Linux)
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y jq shellcheck

      - name: Install jq and shellcheck (macOS)
        if: runner.os == 'macOS'
        run: brew install jq shellcheck

      - name: Validate
        run: sh scripts/validate.sh

      - name: Test
        run: sh tests/run.sh
```

The matrix exists because the scripts run on macOS and Linux and the two differ on `readlink`, `sed`, and `date` — a Linux-only job would not catch a BSD incompatibility before it reached the MacBook.

- [ ] **Step 6: Commit**

```sh
git add scripts/validate.sh tests/test_validate.sh .github/workflows/validate.yml
git commit -m "feat: add validation script and cross-platform CI"
```

---

## Task 12: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the finished behavior of all three scripts.
- Produces: the documentation the spec requires.

- [ ] **Step 1: Write `README.md`**

It must cover, in this order, matching the spec's documentation requirements:

1. **What this is** — personal OpenCode and Claude Code configuration for three machines, public so it can be cloned without authentication and read by others. Not a community project; no contribution process.
2. **What it does not contain** — no credentials (OpenCode uses `~/.local/share/opencode`, Claude Code the system keychain), no session history, no auto memory, no plugin caches.
3. **Supported systems** — macOS, Linux, WSL-as-Linux. Native Windows is out of scope.
4. **Requirements** — `git`, `jq`, a POSIX shell.
5. **Layout** — the tree, with one line per directory saying which tool reads it.
6. **Install**, with the exact commands:
   ```sh
   git clone "$REPOSITORY_URL" ~/.agent-dotfiles
   ~/.agent-dotfiles/scripts/install.sh --all --machine macbook
   ```
   plus the two shell lines the installer prints.
7. **Selective install** — `--claude` and `--opencode` separately.
8. **What a pull updates by itself** — every linked file, and new skills, agents, commands, rules, workflows, output styles, and themes, because directories are linked whole. What it does not: `claude/settings.json` and `claude/machines/*`, which need `install.sh` — closed by `install.sh --hook`.
9. **Per-machine configuration** — how `claude/machines/<name>.json` and `opencode/machines/<name>.json` work, the merge rule (objects merge, arrays replace), and the fact that machine files are committed on purpose so every machine is visible from any machine.
10. **Secrets** — `~/.config/agent-dotfiles/env`, never committed; `{env:VAR}` in OpenCode config.
11. **Conflicts, backups, rollback** — refusal by default, `--force`, where backups live, `uninstall.sh --restore`, and rollback by `git checkout` plus a rerun.
12. **Validation** — `sh scripts/validate.sh`, `sh tests/run.sh`.
13. **Forking** — replace the machine files with your own names; nothing else is machine-specific.
14. **Links** — the four official documentation URLs from the spec's Sources section.

- [ ] **Step 2: Verify the README's commands actually work**

Run every command block in the README verbatim inside a sandbox from `tests/sandbox.sh`. A README command that does not run is a defect; fix the README or the script.

- [ ] **Step 3: Run the full suite one last time**

```sh
sh scripts/validate.sh
sh tests/run.sh
```
Expected: both exit 0.

- [ ] **Step 4: Commit**

```sh
git add README.md
git commit -m "docs: add README covering install, update, and per-machine layering"
```

---

## Final verification

Before declaring the work complete, confirm each spec acceptance criterion by running it, not by reading the code:

- [ ] Fresh clone plus one `install.sh --all --machine NAME` produces a working configuration — check on macOS and in WSL at minimum.
- [ ] `--dry-run` changes nothing (`tests/test_install.sh` asserts it; confirm on a real home too).
- [ ] A second identical run creates no backup and rewrites no link.
- [ ] A conflicting target is refused by default and backed up under `--force`.
- [ ] `uninstall.sh` refuses drifted targets and restores on request.
- [ ] `validate.sh` passes without touching the real home directory, and fails on a malformed machine file for any machine.
- [ ] A skill added on one machine is live on another after `git pull` alone.
- [ ] `git grep -nE '/Users/|/home/' -- shared opencode claude scripts README.md` returns nothing.
- [ ] All seven verification items from Tasks 1-2 are recorded as PASS.
