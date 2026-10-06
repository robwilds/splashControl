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
| `-y, --yes` | — | Skip prompts, use defaults |
| `-s, --skip-update` | — | Skip brew/splash install check |
| `--` | — | Pass extra args to `splash serve` |

## How it works

1. Ensures Homebrew is installed (installs it if missing), then runs `brew update`
2. Ensures `incoai/tap/splash` is installed/up-to-date via Homebrew
3. Prompts for model, idle release, and cache disk (press Enter for defaults)
4. Executes `exec splash serve --language-only --max-cache-disk ... --model ...`

## Gotchas

- The script runs under `#!/bin/sh` (POSIX), not bash-specific features
- Without `-s`, it always updates Homebrew (`brew update`) and splash (`brew upgrade`), which may take time
- Without `-s`, it may install Homebrew if not present (prompts for sudo)
- `--` passes remaining args directly to `splash serve` (not parsed by this script)
