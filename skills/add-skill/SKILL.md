---
name: add-skill
description: Install a third-party skill from GitHub into the agent-dotfiles repository so it works in both Claude Code and OpenCode and follows the user to their other machines. Use when the user wants to add, install, vendor, or update a skill from someone else's repo, or asks why an installed skill did not sync.
---

# Add a third-party skill

Skills written by other people are copied into this repository rather than
installed by a package manager. Both tools read `skills/` through a symlink into
the repo, so one copy serves Claude Code and OpenCode at once, is live without an
install step, and travels with a plain `git pull`.

## Why not `npx skills add`

That tool installs by symlinking the agent's skill directory at a canonical copy
elsewhere on the machine. Here, the agent's skill directory *is* this repository,
so the link would be committed as a relative path that resolves to nothing on any
other machine. `validate.sh` fails the build if such a link appears. If the user
has already run it and a link is sitting in `skills/`, delete the link and vendor
the skill properly with the script below.

## The one rule

**You do not commit.** `add-skill.sh` copies the files and prints the `git`
command; running it is the user's step. Do not offer to commit for them.

## Adding one

```sh
sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/add-skill.sh" owner/repo
```

Add `--skill NAME` when the package holds more than one — the script refuses to
guess and lists what it found, so run it once bare and read the list. `--ref`
pins a branch or tag.

The skill is live in both tools the moment the copy lands. Say which one arrived
and remind the user it is uncommitted.

## Updating and listing

```sh
sh <repo>/scripts/add-skill.sh --update NAME   # refetch from the recorded source
sh <repo>/scripts/add-skill.sh --list          # what came from elsewhere
```

Each vendored skill carries a `.source` file recording where it came from and the
exact commit. A skill with no `.source` was written here, and `--update` refuses
it rather than overwriting the user's own work.

## Situations to report rather than work around

- **The name is already taken.** The script stops. Offer `--force`, which backs up
  the existing copy first — but only after the user confirms, since their own
  edits may be in it.
- **The fetch failed.** Report the source and ref as given. Do not try other URLs
  on the user's behalf; a wrong guess installs someone else's code.
- **Validation fails after adding.** Vendored skills are scanned like everything
  else, so an upstream skill containing an absolute home path will fail the check.
  Show the offending file and let the user decide whether to edit or drop it.
