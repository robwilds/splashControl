#!/bin/sh
# start_splash.sh - launch "splash serve" with overridable settings.
# Values not given on the command line are prompted for interactively
# (press Enter to accept the default shown in brackets).
# Also makes sure Homebrew is installed and splash (incoai/tap/splash)
# is installed / up to date before launching.

# Defaults
MODEL="unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL"
IDLE_RELEASE="90s"
MAX_CACHE_DISK="16G"

# Track which values were supplied on the command line
MODEL_SET=0
IDLE_SET=0
CACHE_SET=0
ASSUME_YES=0
SKIP_UPDATE=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [options] [-- extra splash args]

Any value not given as an option is prompted for (Enter = keep default).

Options:
  -m, --model MODEL             Model to serve (default: $MODEL)
  -i, --idle-release DURATION   Idle release time (default: $IDLE_RELEASE)
  -c, --max-cache-disk SIZE     Max disk cache size (default: $MAX_CACHE_DISK)
  -y, --yes                     Skip prompts and use defaults for unset values
  -s, --skip-update             Skip the Homebrew / splash install-or-update check
  -h, --help                    Show this help

Example:
  $(basename "$0") -m unsloth/Some-Model-GGUF:Q4_K_M -i 120s -c 32G
USAGE
}

need_value() {
    [ -n "$2" ] || { echo "Error: $1 requires a value" >&2; exit 1; }
}

load_brew_env() {
    # Put brew on PATH if it is installed in a standard location
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew \
             /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
        if [ -x "$b" ]; then
            eval "$("$b" shellenv)"
            return 0
        fi
    done
    return 1
}

ensure_brew() {
    command -v brew >/dev/null 2>&1 && return 0
    load_brew_env && command -v brew >/dev/null 2>&1 && return 0

    echo "Homebrew not found - installing from https://brew.sh ..."
    # The installer prompts for confirmation/sudo; run unattended if no terminal
    [ -t 0 ] || export NONINTERACTIVE=1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || { echo "Error: Homebrew installation failed" >&2; exit 1; }

    load_brew_env
    command -v brew >/dev/null 2>&1 \
        || { echo "Error: brew still not found after installation" >&2; exit 1; }
}

ensure_brew_updated() {
    echo "Updating Homebrew ..."
    brew update || { echo "Warning: brew update failed; continuing" >&2; }
}

ensure_splash() {
    if brew list --formula incoai/tap/splash >/dev/null 2>&1; then
        echo "Checking for splash updates..."
        brew upgrade incoai/tap/splash \
            || echo "Warning: splash upgrade failed; continuing with installed version" >&2
    else
        echo "Installing splash..."
        brew install incoai/tap/splash \
            || { echo "Error: splash installation failed" >&2; exit 1; }
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        -m|--model)
            need_value "$1" "$2"; MODEL="$2"; MODEL_SET=1; shift 2 ;;
        --model=*)
            MODEL="${1#*=}"; MODEL_SET=1; shift ;;
        -i|--idle-release)
            need_value "$1" "$2"; IDLE_RELEASE="$2"; IDLE_SET=1; shift 2 ;;
        --idle-release=*)
            IDLE_RELEASE="${1#*=}"; IDLE_SET=1; shift ;;
        -c|--max-cache-disk)
            need_value "$1" "$2"; MAX_CACHE_DISK="$2"; CACHE_SET=1; shift 2 ;;
        --max-cache-disk=*)
            MAX_CACHE_DISK="${1#*=}"; CACHE_SET=1; shift ;;
        -y|--yes)
            ASSUME_YES=1; shift ;;
        -s|--skip-update)
            SKIP_UPDATE=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; break ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1 ;;
    esac
done

# Make sure brew and splash are present / current
if [ "$SKIP_UPDATE" -eq 0 ]; then
    ensure_brew
    ensure_brew_updated
    ensure_splash
else
    load_brew_env >/dev/null 2>&1 || true
fi

# Prompt only if running in a terminal and -y wasn't given
if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
    if [ "$MODEL_SET" -eq 0 ]; then
        printf "Model [%s]: " "$MODEL"
        read -r input
        [ -n "$input" ] && MODEL="$input"
    fi
    if [ "$IDLE_SET" -eq 0 ]; then
        printf "Idle release [%s]: " "$IDLE_RELEASE"
        read -r input
        [ -n "$input" ] && IDLE_RELEASE="$input"
    fi
    if [ "$CACHE_SET" -eq 0 ]; then
        printf "Max cache disk [%s]: " "$MAX_CACHE_DISK"
        read -r input
        [ -n "$input" ] && MAX_CACHE_DISK="$input"
    fi
fi

echo "Starting splash:"
echo "  model:          $MODEL"
echo "  idle-release:   $IDLE_RELEASE"
echo "  max-cache-disk: $MAX_CACHE_DISK"

exec splash serve \
    --language-only \
    --max-cache-disk "$MAX_CACHE_DISK" \
    --idle-release "$IDLE_RELEASE" \
    --model "$MODEL" \
    "$@"
