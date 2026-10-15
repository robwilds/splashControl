# splashControl

Launches a local LLM model server using [splash](https://github.com/incoai/splash) with overridable settings.

## Purpose

`splash serve` starts a local language-model server. This script wraps that
command so you can quickly pick a model, choose an agent to connect, and tune
cache/idle settings without memorising flags. Chosen values are remembered and
reused on the next run.

Splash dramatically improves tok/s as tested on an m5 macbook air with 24gb ram.

Splash currently only supports qwen3.8 and 3.6 models that are specifically formatted for splash. Refer to the splash github repo link above for more details.

## Quick Start

Run the script straight from the repo — it is executable, there is nothing to
install first (Homebrew and `splash` are installed automatically if missing):

```bash
./start_splash.sh
```

On an interactive first run it:

1. Ensures Homebrew and `splash` (`incoai/tap/splash`) are installed and up to
   date (skip this step with `-s`).
2. Prompts for the model, idle-release time, and max disk cache (press Enter to
   accept the default shown in brackets).
3. Offers to install a `splashctl` launcher on your PATH so you can run it from
   anywhere (see [Run from anywhere](#run-from-anywhere)).
4. Starts `splash serve` in the background.
5. Lets you pick what to launch once the model has finished loading: a TUI agent
   (`opencode`, `hermes`, or `claude`), the `browser` web chat UI, or nothing.

Common non-interactive invocations:

```bash
# Accept all defaults, no prompts (no agent is launched unless one is remembered)
./start_splash.sh -y

# Pick a model, use a 32G cache, skip the Homebrew/splash update check
./start_splash.sh -s -m unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL -c 32G

# Launch opencode against the server as soon as it is ready
./start_splash.sh -y -a opencode
```

`./start_splash.sh --help` prints the full option list at any time.

### Options

| Option                        | Default                                   | Description                                                               |
| ----------------------------- | ----------------------------------------- | ------------------------------------------------------------------------- |
| `-m, --model MODEL`           | `unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL` | Model to serve                                                            |
| `-i, --idle-release DURATION` | `90s`                                     | Time until the idle model is released from memory                         |
| `-c, --max-cache-disk SIZE`   | `16G`                                     | Maximum disk cache size for model weights                                 |
| `-a, --agent AGENT`           | `none`                                    | Agent to launch once ready: `none`/`opencode`/`hermes`/`claude`/`browser` |
| `-w, --ready-timeout SECONDS` | `0` (wait forever)                        | How long to wait for the server to become ready before launching an agent |
| `-y, --yes`                   | —                                         | Skip interactive prompts, use defaults                                    |
| `-s, --skip-update`           | —                                         | Skip the Homebrew / splash install-or-update check                        |
| `-l, --live`                  | —                                         | Stream splash output directly to the terminal                             |
| `-k, --kill`                  | —                                         | Stop an existing `splash serve` without prompting                         |
| `--no-save`                   | —                                         | Do not remember the chosen values this run                                |
| `--forget`                    | —                                         | Delete the remembered values and exit                                     |
| `--add-path`                  | —                                         | Install a `splashctl` launcher on your PATH and exit                      |
| `--remove-path`               | —                                         | Remove the `splashctl` launcher and exit                                  |
| `--`                          | —                                         | Pass extra arguments directly to `splash serve`                           |

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

### Model history

The interactive model prompt shows a numbered menu of the current model plus
the models you have entered before (most recent first), capped at 10:

```
Select model:
  1) unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL (current)
  2) unsloth/Another-Model-GGUF:Q4_K_M
  3) enter a new model id
Choice [1-3 / or type a model id]:
```

Press Enter to keep the current model, pick a number, or type a model id. The
history is stored in `.env` as `MODEL_HISTORY` (a `;`-separated list) and is
safe to edit or trim by hand.

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

# Open the web chat UI in a browser once ready
./start_splash.sh -a browser

# Launch splash in background (no agent)
./start_splash.sh -a none

# Stop an existing splash serve and restart without prompting
./start_splash.sh -y -k

# Pass extra flags to splash serve
./start_splash.sh -- --port 8080

# Stream splash output live to the terminal
./start_splash.sh --live
```

When splash starts, it runs in the background. If no agent is selected, splash remains running and you can press Ctrl+Z to suspend it or kill its PID to stop. If an agent is chosen (via prompt or `-a`), the script first waits until the server reports ready (its `/ready` endpoint answers `200`, which happens once the model has finished loading) and only then launches the agent. This avoids `splash <agent>` failing with "No ready Splash server" while the model is still loading. The wait has no timeout by default; pass `-w SECONDS` to bound it. If splash is served on a non-default port (via `--port` or `SPLASH_PORT`), the script passes that port on to the agent.

Before starting, the script stops any existing `splash serve` and anything else
holding the port, prompting first unless `-y`/`-k` was given.

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

- M3 or newer MacBook running macOS 26 or later
- Homebrew (auto-installed if missing, auto-updated each run)
- `splash` from `incoai/tap/splash` (auto-installed if missing, auto-updated each run)
