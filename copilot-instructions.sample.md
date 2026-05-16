# Agent instructions — use `permish` for shell commands

This repository uses `permish`, an OS-enforced sandbox wrapper. **Every shell
command you run must be invoked through `permish [FLAGS] -- <COMMAND>`.**

You — the agent — add flags based on what the command needs to do. The
kernel will enforce your declaration. If you pick the wrong flags, the command
fails with a clear error and you can retry with broader flags.

## Picking the flags

Start with **no flags** (read-only, workspace only) and add only what the command needs:

| If the command…                                          | Flags to add          |
| -------------------------------------------------------- | --------------------- |
| Only reads files **within the workspace** (inspecting code, ripgrep over the repo) | *(none)*              |
| Needs to read files **outside the workspace** (git history that touches submodules, reading another repo, `~/.gitconfig` beyond the basics, system files) | `--read-any`          |
| Writes files in the workspace but doesn’t touch `.git/` or need network | `--write`             |
| Writes files **and** needs network (pip install, npm install, fetching data) | `--write --net`       |
| Modifies git state (commit, checkout, stash, rebase) — git always writes `.git/` | `--write-git`         |
| Pushes, pulls, fetches, or clones (git + network)        | `--write-git --net`   |
| User explicitly asked you to bypass the sandbox          | `--full`              |

## Examples

```bash
# Investigating inside the workspace: no flags needed
permish --              rg "TODO" --type py
permish --              git log --oneline -20
permish --              pytest --collect-only

# Reading something outside the workspace
permish --read-any   -- cat ~/.config/git/config
permish --read-any   -- diff -r . ../other-checkout

# Editing files and running tests: write
permish --write      -- python -m pytest tests/
permish --write      -- python my_script.py

# Need to install something
permish --write --net   -- pip install requests
permish --write --net   -- npm install

# Git mutations
permish --write-git  -- git add -A
permish --write-git  -- git commit -m 'fix: ...'

# Sync with remote
permish --write-git --net -- git push
permish --write-git --net -- git pull --rebase
```

## What happens when you pick wrong

If the command tries to read outside the workspace without `--read-any`, you'll see:

```
... : Operation not permitted
... : No such file or directory
```

If it tries to write without `--write`:

```
... : Read-only file system
```

or for network:

```
... : Network is unreachable
```

When you see those, **don't try to "fix" the command itself**. Re-run it with
the appropriate flags added. The errors are the sandbox doing its job — they
mean the command needed more permissions than you declared.

## Pipelines and subshells

The mode applies to the entire wrapped command, including pipes and subshells:

```bash
# All three of these processes share the same sandbox
permish -- bash -c 'git log --stat | grep -c "^|"'
```

You don't need to wrap each piece individually. Wrap the outer command.

## When NOT to use permish

- Built-in tool calls (`read_file`, `edit_file`, `create_file` etc.) — VS Code
  already enforces workspace boundaries for those. Only wrap commands that go
  through the shell/terminal tool.

- Trivial things like `echo`, `pwd`, `which X` — fine to use `read` mode, or
  just answer from your existing knowledge of the repo.

## If you genuinely need full access

Explain why in your message to the user, then use `--full`. They'll see
the warning banner and can decide. Do not silently escalate to `--full` to make
an error go away — try the narrower flags first.
