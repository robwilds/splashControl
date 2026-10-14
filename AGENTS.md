# splashControl

Single-script repo: `start_splash.sh` launches `splash serve` with overridable settings.

## Quick reference

```
./start_splash.sh -m MODEL -i DURATION -c SIZE
./start_splash.sh --help
```

| Option | Default | Description |
|---|---|---|
| `-m, --model` | `unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL` | Model to serve |
| `-i, --idle-release` | `90s` | Idle release duration |
| `-c, --max-cache-disk` | `16G` | Max disk cache size |
| `-a, --agent` | `none` | Agent to launch (`none`/`opencode`/`hermes`/`claude`) |
| `-l, --live` | — | Stream splash output directly to the terminal |
| `-w, --ready-timeout` | `0` (forever) | Seconds to wait for the server's `/ready` before launching an agent |
| `-y, --yes` | — | Skip prompts, use defaults |
| `-s, --skip-update` | — | Skip brew/splash install check |
| `--no-save` | — | Don't remember this run's values |
| `--forget` | — | Delete the remembered values and exit |
| `--add-path` | — | Install a `splashctl` launcher on PATH and exit |
| `--remove-path` | — | Remove the `splashctl` launcher and exit |
| `--` | — | Pass extra args to `splash serve` |

Values are resolved CLI > `.env` (remembered) > built-in defaults, then saved
back to repo-local `.env` (gitignored). A commented template is checked in as
`.envexample` (tracked) — `cp .envexample .env` to pre-seed values.

## How it works

1. Ensures Homebrew is installed (installs it if missing), then runs `brew update`
2. Ensures `incoai/tap/splash` is installed/up-to-date via Homebrew
3. Loads remembered values from `.env` (if any), then prompts for model, idle release, cache disk, and agent (press Enter for defaults, or use `-y`/`-a` to skip). The resolved values are saved back to `.env`
4. Launches `splash serve` in the background with `--language-only --max-cache-disk ... --model ...`
5. If an agent is chosen (via prompt or `-a`), waits until the server's `/ready` endpoint answers (`splash` reports "Ready" once the model is loaded), then launches the agent with the resolved port

`--add-path`/`--remove-path` are standalone setup actions (run and exit, like
`--forget`). `--add-path` symlinks `~/.local/bin/splashctl` to this script
(override the dir with `SPLASH_CONTROL_BIN`) and, if needed, appends one
idempotent `export PATH=...` line to the shell rc. The first interactive run
also offers this once; the answer is remembered in `.env` as `PATH_ENTRY`
(`yes`/`no`). The script resolves its own symlinks at startup, so invoking it
through the launcher still finds `.env` and `splash.log` in the repo.

## Splash output

- Default: splash's stdout/stderr is captured to `splash.log`. A `tail -f`
  instance streams the log during startup so you can watch model downloads and
  progress messages in real-time.
- `--live` (`-l`): streams splash output directly to the terminal instead of a
  log file. Output is interleaved with the script's own status messages.

## Gotchas

- The script runs under `#!/bin/sh` (POSIX), not bash-specific features
- Without `-s`, it always updates Homebrew (`brew update`) and splash (`brew upgrade`), which may take time
- Without `-s`, it may install Homebrew if not present (prompts for sudo)
- `--` passes remaining args directly to `splash serve` (not parsed by this script)
- `.env` is written automatically each run; use `--no-save` to skip persisting
- `.env` is parsed (not sourced), so values are never executed as code
- `.envexample` is the tracked template; `.env` is gitignored and user-specific
- The PATH launcher is named `splashctl`, not `splash`: the script invokes the
  real `splash` binary internally, so a link named `splash` would recurse
- `--add-path` may append an `export PATH=...` line to `~/.zshrc` /
  `~/.bash_profile` / `~/.bashrc`; `--remove-path` removes it (best-effort)
- `$0` can be the launcher symlink, so the script follows symlinks to find its
  real directory before locating `.env` and `splash.log`
