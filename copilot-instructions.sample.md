# Agent instructions — use `permish` for shell commands

This repository uses `permish`, an OS-enforced sandbox wrapper. **Every shell
command you run must be invoked through `permish --mode <MODE> -- <COMMAND>`.**

You — the agent — pick the mode based on what the command needs to do. The
kernel will enforce your declaration. If you pick the wrong mode, the command
fails with a clear error and you can retry with a different mode.

## Picking the mode

Choose the **least-privilege** mode that lets the command succeed:

| If the command…                                          | Use mode          |
| -------------------------------------------------------- | ----------------- |
| Only reads files (inspecting code, running tests against read-only data, querying git history without checkout) | `read`            |
| Writes files in the workspace but doesn't touch `.git/` or need network | `write`           |
| Writes files **and** needs network (pip install, npm install, fetching data) | `write-net`       |
| Modifies git state (commit, checkout, stash, rebase) — git always writes `.git/` | `write-git`       |
| Pushes, pulls, fetches, or clones (git + network)        | `write-git-net`   |
| User explicitly asked you to bypass the sandbox          | `full`            |

## Examples

```bash
# Investigating: read-only is enough
permish --mode read -- git log --oneline -20
permish --mode read -- rg "TODO" --type py
permish --mode read -- pytest --collect-only

# Editing files and running tests: write
permish --mode write -- python -m pytest tests/
permish --mode write -- python my_script.py

# Need to install something
permish --mode write-net -- pip install requests
permish --mode write-net -- npm install

# Git mutations
permish --mode write-git -- git add -A
permish --mode write-git -- git commit -m 'fix: ...'

# Sync with remote
permish --mode write-git-net -- git push
permish --mode write-git-net -- git pull --rebase
```

## What happens when you pick wrong

If you declare `--mode read` but the command tries to write, you'll see:

```
... : Read-only file system
```

or for network:

```
... : Network is unreachable
```

When you see those, **don't try to "fix" the command itself**. Re-run it with
the correct, broader mode. The errors are the sandbox doing its job — they
mean the command needed more permissions than you declared.

## Pipelines and subshells

The mode applies to the entire wrapped command, including pipes and subshells:

```bash
# All three of these processes share the same sandbox
permish --mode read -- bash -c 'git log --stat | grep -c "^|"'
```

You don't need to wrap each piece individually. Wrap the outer command.

## When NOT to use permish

- Built-in tool calls (`read_file`, `edit_file`, `create_file` etc.) — VS Code
  already enforces workspace boundaries for those. Only wrap commands that go
  through the shell/terminal tool.

- Trivial things like `echo`, `pwd`, `which X` — fine to use `read` mode, or
  just answer from your existing knowledge of the repo.

## If you genuinely need full access

Explain why in your message to the user, then use `--mode full`. They'll see
the warning banner and can decide. Do not silently escalate to `full` to make
an error go away — try the narrower modes first.
