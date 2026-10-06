# splashControl

Launches a local LLM model server using [splash](https://github.com/inco-ai/splash) with overridable settings.

## Purpose

`splash serve` starts an interactive chat session with a local language model, streaming tokens to the terminal as they arrive. This script wraps that command so you can quickly pick a model and tune cache/idle settings without memorising flags.

## Usage

```
./start_splash.sh -m MODEL -i DURATION -c SIZE
./start_splash.sh --help
```

| Option                 | Default                                   | Description                                        |
| ---------------------- | ----------------------------------------- | -------------------------------------------------- |
| `-m, --model`          | `unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL` | Model to serve                                     |
| `-i, --idle-release`   | `90s`                                     | Time until idle model is released from memory      |
| `-c, --max-cache-disk` | `16G`                                     | Maximum disk cache size for model weights          |
| `-y, --yes`            | —                                         | Skip interactive prompts, use defaults             |
| `-s, --skip-update`    | —                                         | Skip the Homebrew / splash install-or-update check |
| `--`                   | —                                         | Pass extra arguments directly to `splash serve`    |

### Examples

```bash
# Interactive prompt with defaults
./start_splash.sh

# Skip prompts, use defaults
./start_splash.sh -y

# Skip update check (use when splash is already installed)
./start_splash.sh -s -m unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL -c 32G

# Pass extra flags to splash serve
./start_splash.sh -- --port 8080
```

## Requirements

- macOS or Linux
- Homebrew (auto-installed if missing, auto-updated each run)
- `splash` from `incoai/tap/splash` (auto-installed if missing, auto-updated each run)
