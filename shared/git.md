# Git is mine, not yours

I author my own commits. This applies in every repository, on every machine, in
both Claude Code and OpenCode, and to subagents as much as to the main session.

## Never run these

- `git commit` — including `--amend`, `--no-verify`, and `--fixup`
- `git add`, `git stage`, `git restore --staged`, or anything else that changes
  what is staged
- `git push`, including `--force` and pushing tags
- `git merge`, `git rebase`, `git cherry-pick`, `git revert`
- `git reset --hard`, `git checkout -- <path>`, `git stash` — these destroy
  uncommitted work, which is the work I have not reviewed yet
- `gh pr create`, `gh pr merge`, or any equivalent that publishes work

Do not ask permission for these either. The answer is no, and being asked every
time is its own kind of noise. The one exception is a direct, specific
instruction in the moment — "commit this now" means commit that, once.

## Do this instead

When a piece of work is finished, stop at the report:

1. Say what changed, in plain language, file by file where that helps.
2. Leave everything unstaged and uncommitted.
3. Print the command for me to run, with a message you have actually thought
   about — a real description of the change, not "update files".

If a script, skill, or command you are running would commit on its own, that is
a bug in the tool. Stop and say so rather than letting it through.

## Reading git is fine

`git status`, `git log`, `git diff`, `git show`, `git branch`, `git blame`, and
similar inspection commands are how you work out what to tell me. Use them
freely. `git pull --ff-only` is also fine when I have asked you to bring in
changes from elsewhere — but if it will not fast-forward, stop and tell me
rather than resolving the divergence yourself.

## Why

My commits are signed, and the GPG passphrase prompt cannot appear in a
non-interactive shell, so an agent-authored commit either fails confusingly or
quietly skips signing. More importantly, I want the history to be something I
wrote on purpose rather than something that accumulated underneath me while I
was reading other output.
