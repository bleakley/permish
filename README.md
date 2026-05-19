# permish

OS-enforced sandbox for AI agent tool calls.

The agent declares what permissions a command needs with flags like `--write`, `--net`, `--write-git`. If the command tries to do more than declared, the **kernel** denies the syscall and the command exits non-zero. You don't have to audit what the command actually does — the OS does it for you.

This is the same idea OpenAI's Codex CLI uses internally (Landlock + seccomp on Linux, Seatbelt on macOS), packaged as a simple standalone wrapper you can put in front of *any* agent — Claude Code, Cursor, VS Code Copilot, or your own scripts.

## Flags

Flags compose freely. Start with no flags (read-only, workspace only) and add what you need:

| Flag            | Effect                                                              |
| --------------- | ------------------------------------------------------------------- |
| *(none)*        | Read only within the workspace. No writes. No network. (default)   |
| `--read-any`    | Allow reading the whole filesystem (other repos, `~/.ssh`, `/etc`, etc.). |
| `--write`       | Write to workspace + a fresh per-invocation `$TMPDIR`. `.git` stays read-only. |
| `--write-git`   | Write to workspace including `.git` (implies `--write`).            |
| `--write-any`   | Write anywhere on the filesystem (implies `--read-any`).            |
| `--net`         | Allow network access.                                               |
| `--full`        | No restrictions. Escape hatch.                                      |

Flags combine: `--read-any --write`, `--write --net`, `--write-git --net`, `--write-any --net`, etc.

`/tmp` is always a fresh tmpfs that disappears when the command exits.

## Why?

The honest answer to "can I trust this complicated `git` pipeline the agent wants to run?" or "can I trust this 100 line data transformation script?" is usually "I don't know, and I don't want to read it." `permish` lets you stop reading the command and start trusting the *declared mode* instead:

- **Agent right** → command does what it claimed → exits 0, you got your answer.
- **Agent wrong** → command tries to write `.git` or hit the network → kernel denies it, command exits non-zero, no damage done. You see the failure and intervene.

If you add `permish -- ` and `permish --write -- ` to your auto approve list and instruct and instruct your agent to preface every terminal command with `permish`, you will avoid having to auto approve almost all regular commands that your agent runs, including things like bespoke one-off scripts that you can't normally auto approve. You will cut back on time wasting clicks and the kind of approval fatigue that would let a meaningful failure creep by.

## Install

### Linux

```bash
sudo apt install bubblewrap
sudo install -m 0755 permish /usr/local/bin/permish
```

### macOS

```bash
sudo install -m 0755 permish /usr/local/bin/permish
```

## Usage

```bash
permish                   -- grep -r TODO .               # read only within workspace (default)
permish --read-any        -- git log --stat master..HEAD  # need to read outside the workspace
permish --write           -- python process.py
permish --write --net     -- pip install requests         # in a venv inside the workspace
permish --write-any --net -- pip install --user requests  # touches ~/.local
permish --write-git       -- git commit -am 'wip'
permish --write-git --net -- git push
permish --full            -- some-command-you-fully-trust
```

### Options

| Flag                  | Effect                                                               |
| --------------------- | -------------------------------------------------------------------- |
| `--read-any`          | Allow reading the whole filesystem (default: workspace only).        |
| `--write`             | Allow writing to workspace + a fresh per-invocation `$TMPDIR`. `.git` stays read-only. |
| `--write-git`         | Allow writing to workspace including `.git` (implies `--write`).     |
| `--write-any`         | Allow writing anywhere on the filesystem (implies `--read-any`).     |
| `--net`               | Allow network access.                                                |
| `--full`              | No restrictions.                                                     |
| `--workspace PATH`    | Override workspace root (default: cwd). Writes are confined to here. |
| `--read-path PATH`    | Grant extra read-only path. Repeatable.                              |
| `--write-path PATH`   | Grant extra writable path beyond workspace. Repeatable.              |
| `--quiet`             | Suppress the `[permish]` banner that prints to stderr.               |
| `--explain`           | Print the sandbox command that would run, then exit 0.               |

### What "reads" actually means

By default, `permish` blocks reads of file contents in the sensitive parts of the filesystem: every user's home dir (`/Users/*` on macOS, `/home/*` on Linux), mounted drives (`/Volumes`), and root's data. The workspace itself is re-allowed, along with:

- `~/.gitconfig`, `~/.config/` (so `git` works out of the box)
- Any first-level directory under `$HOME` that appears in `$PATH` — e.g. `~/.nvm`, `~/.pyenv`, `~/.volta`, `~/.rbenv`. The user already made an explicit trust decision by putting those bin dirs on their path.

System paths (`/usr`, `/etc`, `/System`, `/Library`) stay readable so programs can find their interpreter, shared libs, and dyld cache.

Everything else under those blocked trees — `~/.ssh`, other projects under your home dir, mounted disks, another user's files — is unreadable until you pass `--read-any`. Use `--read-path PATH` to grant access to one specific extra location instead of opening up the whole filesystem.

### What "writes" actually means

`permish --write` blocks writes everywhere on the filesystem **except**:

- The workspace directory and below (with `.git` carved out as read-only)
- A fresh per-invocation temp directory on macOS (see `$TMPDIR` handling below) or a fresh `tmpfs` at `/tmp` on Linux.
- Any extra path you pass with `--write-path`

So your home directory, system Python's site-packages, `/etc`, etc., are all read-only. Use `--write-any` if the command needs to write outside the workspace (e.g. `pip install --user`, `npm install -g`, writing to `~/.cache`). `.git` is still protected unless you also pass `--write-git`.

### `$TMPDIR` handling

`permish` uses an isolated temp directory and points `$TMPDIR` at it. The standard temp APIs (Python `tempfile`, Go `os.TempDir`, Rust `env::temp_dir`, `NSTemporaryDirectory`, libc `mkstemp` with `-t`, Node `os.tmpdir`) pick it up transparently.

Tools that hardcode `/tmp/...` paths and ignore `$TMPDIR` will see `Operation not permitted` on macOS. Pass `--write-path /tmp` if you need to support this.

### What "no network" actually means

On Linux, the command runs in its own network namespace with no interfaces. `connect()` fails with `ENETUNREACH`. Localhost binds also fail because there's no `lo` interface.

On macOS, outbound network is denied via Seatbelt. Localhost is allowed by default (because tons of tooling needs it); if you want truly zero network including loopback, edit the profile.

## Using it with VS Code Copilot agent

Make the agent prefix every shell command with `permish [FLAGS] -- ...`, then use VS Code's terminal auto-approve to whitelist `permish` invocations by flags.

### 1. Tell the agent to use it

This repo has a sample `copilot-instructions.md` you can use either in your project or user level prompts. You can also instruct the agent to write a memory about `permish`. There are many options here.

### 2. Auto-approve sandboxed commands in `settings.json`

```json
{
  "chat.tools.terminal.autoApprove": {
    "/^permish -- /": true,
    "/^permish --read-any -- /": true,
    "/^permish --write -- /": true
  }
}
```

Any `permish` invocation not matched by a `true` pattern will fall through and require explicit approval.

Alternatively, you can use negative lookaheads so that flag order is irrelevant, and you can auto-approve all permish commands that don't contain forbidden flags:

```json
{
  "chat.tools.terminal.autoApprove": {
    "/^permish(?!.* --(write-any|write-git|net|full)).* -- /": true,
  }
}
```
