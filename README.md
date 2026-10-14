# splashControl

Launches a local LLM model server using [splash](https://github.com/inco-ai/splash) with overridable settings.

## Purpose

`splash serve` starts an interactive chat session with a local language model, streaming tokens to the terminal as they arrive. This script wraps that command so you can quickly pick a model and tune cache/idle settings without memorising flags.

## Usage

```
./start_splash.sh -m MODEL -i DURATION -c SIZE
./start_splash.sh --help
```

| Option                      | Default                                   | Description                                       |
| --------------------------- | ----------------------------------------- | ------------------------------------------------- |
| `-m, --model MODEL`         | `unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL` | Model to serve                                    |
| `-i, --idle-release DURATION` | `90s`                                   | Time until idle model is released from memory     |
| `-c, --max-cache-disk SIZE` | `16G`                                     | Maximum disk cache size for model weights         |
| `-a, --agent AGENT`         | `none`                                    | Agent to launch (`none`/`opencode`/`hermes`/`claude`) |
| `-w, --ready-timeout SECONDS` | `0` (wait forever)                      | How long to wait for the server to become ready before launching an agent |
| `-y, --yes`                 | —                                         | Skip interactive prompts, use defaults            |
| `-s, --skip-update`         | —                                         | Skip the Homebrew / splash install-or-update check |
| `-l, --live`                | —                                         | Stream splash output directly to the terminal     |
| `--no-save`                 | —                                         | Do not remember the chosen values this run       |
| `--forget`                  | —                                         | Delete the remembered values and exit            |
| `--add-path`                | —                                         | Install a `splashctl` launcher on your PATH and exit |
| `--remove-path`             | —                                         | Remove the `splashctl` launcher and exit         |
| `--`                        | —                                         | Pass extra arguments directly to `splash serve`   |

### Remembered settings

Every run resolves values in this order — **CLI options win, then the
remembered `.env`, then the built-in defaults** — and saves the final model,
idle release, cache size, agent, and PATH-launcher choice back to `.env`:

```
./start_splash.sh -m unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL -c 32G
# next run: those values are now the defaults shown in the prompts
./start_splash.sh
```

`.env` lives next to the script and is gitignored. You can edit it by hand
(say, to settle on a model), delete it to start fresh, or point the script at
another file with `SPLASH_CONTROL_ENV=/path/to/.env`. Use `--no-save` for a
one-off run you don't want remembered, and `--forget` to wipe the file.

A commented template is checked in as [`.envexample`](./.envexample) — copy it
to `.env` to pre-seed your preferred values:

```
cp .envexample .env
```

### Run from anywhere

`--add-path` installs a `splashctl` launcher (a symlink to this script) so you
can run splashControl from any directory:

```
./start_splash.sh --add-path   # creates ~/.local/bin/splashctl and adds it to PATH
splashctl                      # from anywhere
./start_splash.sh --remove-path
```

- The link is created in `~/.local/bin` (override with `SPLASH_CONTROL_BIN=/some/bin`).
- If that directory is not already on your `PATH`, the script appends one
  idempotent `export PATH=...` line to your shell startup file (`~/.zshrc`,
  `~/.bash_profile`, or `~/.bashrc`). Open a new terminal, or `source` the file,
  to pick it up.
- The first interactive run also offers this once; the answer is remembered in
  `.env` as `PATH_ENTRY` (`yes`/`no`). Non-interactive runs (`-y`) never install
  it unless you previously said yes.
- The launcher is deliberately named `splashctl`, **not** `splash`: this script
  calls the real `splash` binary internally, and a link called `splash` would
  make it re-invoke itself.
- Only a symlink pointing at this script is ever removed/overwritten; a
  pre-existing unrelated file of the same name is left untouched.

### Examples

```bash
# Interactive prompt with defaults
./start_splash.sh

# Skip prompts, use defaults
./start_splash.sh -y

# Skip update check (use when splash is already installed)
./start_splash.sh -s -m unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL -c 32G

# Select an agent non-interactively
./start_splash.sh -a opencode

# Launch splash in background (no agent)
./start_splash.sh -a none

# Pass extra flags to splash serve
./start_splash.sh -- --port 8080

# Stream splash output live to the terminal
./start_splash.sh --live
```

When splash starts, it runs in the background. If no agent is selected, splash remains running and you can press Ctrl+Z to suspend it or kill its PID to stop. If an agent is chosen (via prompt or `-a`), the script first waits until the server reports ready (its `/ready` endpoint answers `200`, which happens once the model has finished loading) and only then launches the agent. This avoids `splash <agent>` failing with "No ready Splash server" while the model is still loading. The wait has no timeout by default; pass `-w SECONDS` to bound it. If splash is served on a non-default port (via `--port` or `SPLASH_PORT`), the script passes that port on to the agent.

### Splash output

By default splash's output is captured to `splash.log` in the same directory as
the script. While waiting for the server to become ready, `tail -f` streams the
log to your terminal so you can watch model downloads and progress messages in
real-time. You can also inspect it at any time:

```bash
tail -f splash.log
```

Pass `--live` (or `-l`) to stream splash output directly to the terminal instead
of a log file. Note that the output will be interleaved with the script's own
status messages (the spinner, agent startup text, etc.).

## Requirements

- macOS or Linux
- Homebrew (auto-installed if missing, auto-updated each run)
- `splash` from `incoai/tap/splash` (auto-installed if missing, auto-updated each run)
