---
description: Install a third-party skill into the agent-dotfiles repository so both tools and every machine get it
---

Vendor a third-party skill into this repository. One copy under `skills/` is read
by Claude Code and OpenCode alike, is live immediately, and travels with a pull.

**Do not commit.** The script prints the `git` command; running it is the user's.

## Add

!`sh "$(jq -r .repo "${XDG_STATE_HOME:-$HOME/.local/state}/agent-dotfiles/manifest.json")/scripts/add-skill.sh" --list`

That lists what is already vendored. To add one:

```sh
sh <repo>/scripts/add-skill.sh owner/repo [--skill NAME] [--ref REF]
```

Run it bare first when the package may hold several skills — it refuses to guess
and prints the names it found.

## Update

```sh
sh <repo>/scripts/add-skill.sh --update NAME
```

Refetches from the `.source` file recorded at install time. A skill without one
was authored here and is left alone.

## Do not use `npx skills add`

It symlinks into the agent directory, which here is this repository — the link
would be committed and resolve to nothing on another machine. `validate.sh` fails
on any symlink under `skills/`.

## Report, do not work around

- **Name already taken**: `--force` backs up first, but confirm with the user.
- **Fetch failed**: report the source as given; do not guess other URLs.
