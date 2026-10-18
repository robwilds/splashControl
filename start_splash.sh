#!/bin/sh
# start_splash.sh - launch "splash serve" with overridable settings.
# Values not given on the command line are prompted for interactively
# (press Enter to accept the default shown in brackets). Chosen values are
# remembered in .env and reused as the defaults on the next run.
# Also makes sure Homebrew is installed and splash (incoai/tap/splash)
# is installed / up to date before launching.

# Defaults
MODEL="unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL"
# Models entered before, most recent first. Stored as a single ';'-separated
# value in .env (model ids never contain ';'), so the model prompt can offer
# the current and previously entered models as a numbered menu.
MODEL_HISTORY=""
MODEL_HISTORY_SEP=";"
MODEL_HISTORY_MAX=10
IDLE_RELEASE="90s"
MAX_CACHE_DISK="16G"
# Context token limit passed as --max-context (splash accepts e.g. 100K,
# where K = 1024 tokens); 100K is the splashControl default.
MAX_CONTEXT="100K"
AGENT="none"
# Seconds to wait for the server's /ready before giving up when launching an
# agent. 0 waits indefinitely (until the server is ready or splash exits).
READY_TIMEOUT=0
# Whether to stream splash output directly to the terminal (--live).
# When false, output is captured to splash.log and tailed during startup.
STREAM_SPLASH=0
# splash serve's default HTTP port
DEFAULT_PORT=8000

# On-PATH launcher so this script can be run from anywhere. The name is
# deliberately NOT "splash": this script calls the real splash binary
# internally, so a link called "splash" would re-invoke this script forever.
LINK_NAME="splashctl"
# Directory the launcher symlink is created in. Override with
# SPLASH_CONTROL_BIN=/some/bin (e.g. /usr/local/bin).
INSTALL_DIR="${SPLASH_CONTROL_BIN:-$HOME/.local/bin}"
# Remembered preference for the PATH prompt: "" (ask) / "yes" / "no"
PATH_ENTRY=""

# This script's real location. $0 can be the on-PATH launcher symlink (in a
# bin directory, not the repo), so follow symlinks before locating .env and
# splash.log next to the real script.
SCRIPT_SELF="$0"
while [ -L "$SCRIPT_SELF" ]; do
    link_target=$(readlink "$SCRIPT_SELF")
    case "$link_target" in
        /*) SCRIPT_SELF="$link_target" ;;
        *)  SCRIPT_SELF="$(dirname -- "$SCRIPT_SELF")/$link_target" ;;
    esac
done
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_SELF")" && pwd)
SCRIPT_FILE="$SCRIPT_DIR/$(basename -- "$SCRIPT_SELF")"
CONFIG_FILE="${SPLASH_CONTROL_ENV:-$SCRIPT_DIR/.env}"

# Track which values were supplied on the command line
MODEL_SET=0
IDLE_SET=0
CACHE_SET=0
CONTEXT_SET=0
AGENT_SET=0
LIVE_SET=0
ASSUME_YES=0
SKIP_UPDATE=0
SAVE_CONFIG=1
FORGET_CONFIG=0
FORCE_KILL=0
ADD_PATH=0
REMOVE_PATH=0
# Set when the user clears the model history from the selection menu.
CLEAR_HISTORY=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [options] [-- extra splash args]

Any value not given as an option is prompted for (Enter = keep default).

Options:
  -m, --model MODEL             Model to serve (default: $MODEL)
  -i, --idle-release DURATION   Idle release time (default: $IDLE_RELEASE)
  -c, --max-cache-disk SIZE     Max disk cache size (default: $MAX_CACHE_DISK)
  -C, --max-context TOKENS      Context token limit (default: $MAX_CONTEXT)
  -y, --yes                     Skip prompts and use defaults for unset values
  -s, --skip-update             Skip the Homebrew / splash install-or-update check
  -a, --agent AGENT             Agent to launch (none/opencode/hermes/claude/browser)
  -l, --live                    Stream splash output to terminal directly
  -k, --kill                    Stop existing splash serve without prompting
  -w, --ready-timeout SECONDS   Give up waiting for the server after SECONDS
                                when launching an agent (0 = wait forever)
      --no-save                 Do not remember the chosen values this run
      --forget                  Delete the remembered values and exit
      --add-path                Install a 'splashctl' launcher on your PATH
                                (see below) and exit
      --remove-path             Remove the 'splashctl' launcher and exit
  -h, --help                    Show this help

Before launching an agent the script waits until the local server answers
/ready (splash reports "Ready" once the model is loaded), so the agent does
not start against a server that is still loading.

When prompting for the model, the current model and models entered before are
offered as a numbered menu (stored in $CONFIG_FILE), including an option to
clear the model history.

Chosen values are remembered in:
  $CONFIG_FILE
and reused as the defaults on the next run. Command-line options always win.

Run from anywhere:
  '$LINK_NAME' is a symlink to this script, created in $INSTALL_DIR (override
  with SPLASH_CONTROL_BIN). With --add-path it is installed and $INSTALL_DIR is
  added to your shell's PATH if needed; the first interactive run also offers
  this once. Use --remove-path to unlink it again. The name is not 'splash' so
  the real splash binary this script invokes is left untouched.

Example:
  $(basename "$0") -m unsloth/Some-Model-GGUF:Q4_K_M -i 120s -c 32G
USAGE
}

need_value() {
    [ -n "$2" ] || { echo "Error: $1 requires a value" >&2; exit 1; }
}

# Read remembered values (KEY=value lines) into the current defaults.
# Deliberately a tiny parser rather than sourcing the file.
load_config() {
    [ -f "$CONFIG_FILE" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | tr -d '\r')
        case "$line" in
            ''|\#*) continue ;;
        esac
        key=${line%%=*}
        val=${line#*=}
        case "$val" in
            \"*\") val=${val#\"}; val=${val%\"} ;;
            \'*\') val=${val#\'}; val=${val%\'} ;;
        esac
        case "$key" in
            MODEL)          MODEL="$val" ;;
            MODEL_HISTORY)  MODEL_HISTORY="$val" ;;
            IDLE_RELEASE)   IDLE_RELEASE="$val" ;;
            MAX_CACHE_DISK) MAX_CACHE_DISK="$val" ;;
            MAX_CONTEXT)    MAX_CONTEXT="$val" ;;
            AGENT)          AGENT="$val" ;;
            PATH_ENTRY)     PATH_ENTRY="$val" ;;
        esac
    done < "$CONFIG_FILE"
}

# Write the resolved values back so the next run can reuse them.
save_config() {
    [ "$SAVE_CONFIG" -eq 1 ] || return 0
    mkdir -p -- "$(dirname -- "$CONFIG_FILE")" 2>/dev/null || true
    tmp="${CONFIG_FILE}.tmp.$$"
    umask 077
    cat > "$tmp" <<__EOF__
# splashControl remembered settings (auto-generated; safe to edit or delete)
MODEL=$MODEL
MODEL_HISTORY=$MODEL_HISTORY
IDLE_RELEASE=$IDLE_RELEASE
MAX_CACHE_DISK=$MAX_CACHE_DISK
MAX_CONTEXT=$MAX_CONTEXT
AGENT=$AGENT
PATH_ENTRY=$PATH_ENTRY
__EOF__
    mv -- "$tmp" "$CONFIG_FILE"
}

# Remember the model just used at the front of the history (most recent first),
# dropping duplicates and keeping at most MODEL_HISTORY_MAX entries.
record_model() {
    # A user-initiated clear from the selection menu skips re-recording, so the
    # saved history stays empty until a new model is actually chosen.
    [ "$CLEAR_HISTORY" -eq 1 ] && return 0
    [ -n "$MODEL" ] || return 0
    new_history="$MODEL"
    count=1
    old_ifs=$IFS
    IFS="$MODEL_HISTORY_SEP"
    for m in $MODEL_HISTORY; do
        [ -n "$m" ] || continue
        [ "$m" = "$MODEL" ] && continue
        new_history="$new_history$MODEL_HISTORY_SEP$m"
        count=$((count + 1))
        [ "$count" -ge "$MODEL_HISTORY_MAX" ] && break
    done
    IFS=$old_ifs
    MODEL_HISTORY="$new_history"
}

# Present the current model and previously entered models as a numbered menu.
# Press Enter to keep the current model, pick a number, type a model id, or pick
# the trailing option to clear the saved model history.
select_model() {
    printf "Select model:\n"
    printf "  1) %s (current)\n" "$MODEL"
    menu_count=1
    menu_models="$MODEL"
    old_ifs=$IFS
    IFS="$MODEL_HISTORY_SEP"
    for m in $MODEL_HISTORY; do
        [ -n "$m" ] || continue
        [ "$m" = "$MODEL" ] && continue
        menu_count=$((menu_count + 1))
        printf "  %s) %s\n" "$menu_count" "$m"
        menu_models="$menu_models$MODEL_HISTORY_SEP$m"
    done
    IFS=$old_ifs
    new_option=$((menu_count + 1))
    clear_option=$((new_option + 1))
    printf "  %s) enter a new model id\n" "$new_option"
    printf "  %s) clear model history\n" "$clear_option"
    printf "Choice [1-%s / or type a model id]: " "$clear_option"
    read -r model_choice || model_choice=""
    case "$model_choice" in
        '')
            : ;;  # keep the current model
        *[!0-9]*)
            MODEL="$model_choice" ;;  # a literal model id typed by the user
        *)
            if [ "$model_choice" -eq "$clear_option" ]; then
                # Drop the saved history but keep serving the current model.
                CLEAR_HISTORY=1
                MODEL_HISTORY=""
                printf "Model history cleared.\n"
            elif [ "$model_choice" -eq "$new_option" ]; then
                printf "Model id: "
                read -r input || input=""
                [ -n "$input" ] && MODEL="$input"
            elif [ "$model_choice" -ge 1 ] && [ "$model_choice" -le "$menu_count" ]; then
                MODEL=$(printf '%s' "$menu_models" | cut -d"$MODEL_HISTORY_SEP" -f "$model_choice")
            else
                printf "Invalid choice; keeping current model.\n" >&2
            fi ;;
    esac
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

# ---------------------------------------------------------------------------
# On-PATH launcher ("run from anywhere")
# ---------------------------------------------------------------------------

# True when the launcher path is a symlink that resolves to this script.
link_target_is_ours() {
    link_file="$INSTALL_DIR/$LINK_NAME"
    [ -L "$link_file" ] || return 1
    dest=$(readlink "$link_file" 2>/dev/null) || return 1
    case "$dest" in
        /*) ;;
        *) dest="$(dirname -- "$link_file")/$dest" ;;
    esac
    [ "$dest" = "$SCRIPT_FILE" ]
}

# Make sure $INSTALL_DIR is on PATH; if not, add one idempotent export line to
# the user's shell startup file (falling back to printing instructions).
ensure_dir_on_path() {
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) return 0 ;;
    esac

    line="export PATH=\"$INSTALL_DIR:\$PATH\""

    case "$(basename -- "${SHELL:-}")" in
        zsh)  rc_file="$HOME/.zshrc" ;;
        bash)
            if [ "$(uname -s)" = "Darwin" ]; then
                rc_file="$HOME/.bash_profile"
            else
                rc_file="$HOME/.bashrc"
            fi ;;
        *) rc_file="" ;;
    esac

    if [ -z "$rc_file" ]; then
        echo "Note: $INSTALL_DIR is not on your PATH."
        echo "Add this to your shell's startup file:"
        echo "  $line"
        return 0
    fi

    if [ -f "$rc_file" ] && grep -Fqx "$line" "$rc_file" 2>/dev/null; then
        return 0
    fi

    {
        printf '\n# Added by splashControl\n'
        printf '%s\n' "$line"
    } >> "$rc_file" \
        || { echo "Warning: could not update $rc_file; add manually: $line" >&2; return 0; }

    echo "Added $INSTALL_DIR to PATH in $rc_file."
    echo "Open a new terminal (or run: source $rc_file) to use '$LINK_NAME'."
}

# Create the launcher symlink and make sure its directory is on PATH.
install_path_link() {
    link_file="$INSTALL_DIR/$LINK_NAME"

    if [ -e "$link_file" ] && [ ! -L "$link_file" ]; then
        echo "Warning: $link_file exists and is not a symlink; not overwriting." >&2
        return 1
    fi
    if [ -L "$link_file" ] && ! link_target_is_ours; then
        echo "Warning: $link_file points elsewhere ($(readlink "$link_file")); not overwriting." >&2
        return 1
    fi

    mkdir -p -- "$INSTALL_DIR" \
        || { echo "Error: could not create $INSTALL_DIR" >&2; return 1; }

    # The launcher executes this script, so it must be executable.
    [ -x "$SCRIPT_FILE" ] || chmod +x "$SCRIPT_FILE" 2>/dev/null || true

    ln -sfn -- "$SCRIPT_FILE" "$link_file" \
        || { echo "Error: could not create $link_file" >&2; return 1; }
    echo "Installed launcher: $link_file -> $SCRIPT_FILE"

    ensure_dir_on_path
    return 0
}

# Remove the launcher symlink (only if it is ours) and the PATH line we added.
remove_path_link() {
    link_file="$INSTALL_DIR/$LINK_NAME"
    removed=0

    if [ -L "$link_file" ]; then
        if link_target_is_ours; then
            rm -f -- "$link_file"
            echo "Removed $link_file."
            removed=1
        else
            echo "Warning: $link_file is not a splashControl link; leaving it alone." >&2
        fi
    fi

    # Best-effort: drop the PATH line we added, if present.
    line="export PATH=\"$INSTALL_DIR:\$PATH\""
    for rc_file in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
        [ -f "$rc_file" ] || continue
        if grep -Fqx "$line" "$rc_file" 2>/dev/null; then
            tmp="$rc_file.splashctl.$$"
            awk -v line="$line" '
                $0 == line { next }
                /^# Added by splashControl/ { next }
                { print }
            ' "$rc_file" > "$tmp" && mv -- "$tmp" "$rc_file"
            echo "Removed the PATH line from $rc_file."
        fi
    done

    [ "$removed" -eq 1 ] || echo "Nothing to remove at $link_file."
    return 0
}

# The port splash serve will listen on: an explicit --port in the extra serve
# args wins, then $SPLASH_PORT, then splash's own default (8000).
resolve_port() {
    prev=
    for arg in "$@"; do
        if [ "$prev" = "--port" ]; then
            PORT="$arg"; return 0
        fi
        case "$arg" in
            --port=*) PORT="${arg#--port=}"; return 0 ;;
        esac
        prev="$arg"
    done
    PORT="${SPLASH_PORT:-$DEFAULT_PORT}"
}

# Find and optionally stop any existing splash serve process.
# Prompts the user unless ASSUME_YES or FORCE_KILL is set.
stop_existing_splash() {
    # Collect PIDs to kill: splash serve + its children, plus anything else on the port.
    to_kill=""
    existing=$(pgrep -f "splash serve" 2>/dev/null)
    if [ -n "$existing" ]; then
        echo "Existing splash serve found (PID $existing)"
        for p in $existing $(pgrep -P "$existing" 2>/dev/null); do
            to_kill="$to_kill $p"
        done
    fi

    # Also grab everything else listening on the port (avoids missing non-splash holders).
    extra=$(lsof -t -i :"$PORT" -sTCP:LISTEN 2>/dev/null)
    if [ -n "$extra" ]; then
        echo "  Port $PORT held by PID(s) $extra"
        for p in $extra; do
            case " $to_kill " in *" $p "*) ;; *) to_kill="$to_kill $p" ;; esac
        done
    fi

    if [ -z "$(echo $to_kill)" ]; then
        return 0
    fi

    # Ask before killing unless user said -y or -k
    if [ "$ASSUME_YES" -eq 1 ] || [ "$FORCE_KILL" -eq 1 ]; then
        echo "Stopping it..."
    else
        printf "Stop it and continue? [y/N]: "
        read -r confirm || confirm=""
        case "$confirm" in
            [Yy]*) echo "Stopping it..." ;;
            *)
                echo "Refused to stop existing process; exiting." >&2
                exit 0
                ;;
        esac
    fi

    # Kill everything we found
    for p in $to_kill; do
        kill -9 "$p" 2>/dev/null
    done

    # Wait for the port to become free (up to 20s).
    waited=0
    while [ "$waited" -lt 20 ]; do
        if ! lsof -i :"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Final check — if still stuck, show what's holding it.
    if lsof -i :"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "Port $PORT still occupied after kill. PIDs holding it:" >&2
        lsof -i :"$PORT" -sTCP:LISTEN 2>/dev/null >&2
        echo "Exiting." >&2
        exit 1
    fi
}

# True once the local server reports ready on $PORT. /ready answers 200 only
# after the model is loaded and 503 while it loads, and it is exempt from the
# server's API key, so no auth header is needed.
server_ready() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/ready" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null --timeout=2 "http://127.0.0.1:$PORT/ready" 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys, urllib.request; urllib.request.urlopen("http://127.0.0.1:%s/ready" % sys.argv[1], timeout=2)' "$PORT" >/dev/null 2>&1
    else
        # Last resort: at least wait for something to listen on the port.
        command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1
    fi
}

# Wait for the server to become ready, so an agent is not launched against a
# server that is still loading the model. Aborts early if serve exits.
# If output was captured to a log file, also tails it so you can watch progress.
wait_for_server() {
    waited=0
    LOGFILE="$SCRIPT_DIR/splash.log"

    # Start tail -f so you can watch splash's output in real-time (only if
    # we captured to a log file, i.e. --live was not set).
    TAIL_PID=""
    if [ "$STREAM_SPLASH" -eq 0 ] && [ -f "$LOGFILE" ]; then
        printf "Watching splash output (see $LOGFILE)...\n\n"
        tail -f -- "$LOGFILE" &
        TAIL_PID=$!
        disown "$TAIL_PID" 2>/dev/null || true
    fi

    printf "Waiting for splash on port %s (model load can take a while)...\n" "$PORT"
    while :; do
        if ! kill -0 "$SPINNER" 2>/dev/null; then
            [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
            printf "\nError: splash serve exited before it became ready.\n" >&2
            return 1
        fi
        if server_ready; then
            [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
            printf "\nSplash is ready on port %s.\n" "$PORT"
            return 0
        fi
        if [ "$READY_TIMEOUT" -gt 0 ] && [ "$waited" -ge "$READY_TIMEOUT" ]; then
            [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
            printf "\nError: splash was not ready on port %s after %ss. Still starting; try 'splash %s' once it reports Ready.\n" \
                "$PORT" "$READY_TIMEOUT" "$AGENT" >&2
            return 1
        fi
        sleep 2
        waited=$((waited + 2))
        [ $((waited % 10)) -eq 0 ] && printf "  still waiting for splash on port %s ... %ss\n" "$PORT" "$waited"
    done
}

# Reuse previously remembered values as the new defaults
load_config

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
        -C|--max-context)
            need_value "$1" "$2"; MAX_CONTEXT="$2"; CONTEXT_SET=1; shift 2 ;;
        --max-context=*)
            MAX_CONTEXT="${1#*=}"; CONTEXT_SET=1; shift ;;
        -y|--yes)
            ASSUME_YES=1; shift ;;
        -s|--skip-update)
            SKIP_UPDATE=1; shift ;;
        -k|--kill)
            FORCE_KILL=1; shift ;;
        -a|--agent)
            need_value "$1" "$2"; AGENT="$2"; AGENT_SET=1; shift 2 ;;
        --agent=*)
            AGENT="${1#*=}"; AGENT_SET=1; shift ;;
        -l|--live)
            STREAM_SPLASH=1; LIVE_SET=1; shift ;;
        -w|--ready-timeout)
            need_value "$1" "$2"
            case "$2" in
                ''|*[!0-9]*)
                    echo "Error: --ready-timeout must be a non-negative integer" >&2
                    exit 1 ;;
            esac
            READY_TIMEOUT="$2"; shift 2 ;;
        --ready-timeout=*)
            READY_TIMEOUT="${1#*=}"
            case "$READY_TIMEOUT" in
                ''|*[!0-9]*)
                    echo "Error: --ready-timeout must be a non-negative integer" >&2
                    exit 1 ;;
            esac
            shift ;;
        --no-save)
            SAVE_CONFIG=0; shift ;;
        --forget)
            FORGET_CONFIG=1; shift ;;
        --add-path)
            ADD_PATH=1; shift ;;
        --remove-path)
            REMOVE_PATH=1; shift ;;
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

if [ "$FORGET_CONFIG" -eq 1 ]; then
    rm -f -- "$CONFIG_FILE"
    echo "Forgot remembered settings ($CONFIG_FILE)."
    exit 0
fi

# Install / remove the on-PATH launcher and exit (setup actions, no serving).
if [ "$ADD_PATH" -eq 1 ] || [ "$REMOVE_PATH" -eq 1 ]; then
    [ "$ADD_PATH" -eq 1 ] && { install_path_link || exit 1; }
    [ "$REMOVE_PATH" -eq 1 ] && remove_path_link
    exit 0
fi

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
        select_model
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
    if [ "$CONTEXT_SET" -eq 0 ]; then
        printf "Max context [%s]: " "$MAX_CONTEXT"
        read -r input
        [ -n "$input" ] && MAX_CONTEXT="$input"
    fi
fi

# Ensure the on-PATH launcher if previously opted in, otherwise offer it once
# (interactive runs only). The choice is remembered in PATH_ENTRY.
if [ "$PATH_ENTRY" = "yes" ]; then
    link_target_is_ours || install_path_link || true
elif [ "$PATH_ENTRY" != "no" ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
    printf "Add '%s' to PATH (%s) so you can launch splashControl from anywhere? [y/N]: " \
        "$LINK_NAME" "$INSTALL_DIR"
    read -r path_answer || path_answer=""
    case "$path_answer" in
        [Yy]*) PATH_ENTRY=yes; install_path_link || true ;;
        *)     PATH_ENTRY=no ;;
    esac
fi

# Remember the model/idle/cache/context choices for next time
record_model
save_config

echo "Starting splash:"
echo "  model:          $MODEL"
echo "  idle-release:   $IDLE_RELEASE"
echo "  max-cache-disk: $MAX_CACHE_DISK"
echo "  max-context:    $MAX_CONTEXT"
echo "  agent:          $AGENT"

# Which port the server and a later agent should use
resolve_port "$@"

stop_existing_splash "$@"

# Start splash serve. By default output is captured to splash.log; with --live
# it streams directly to the terminal (so you see model download progress in
# real-time, but the spinner and agent startup text will also appear).
if [ "$STREAM_SPLASH" -eq 1 ]; then
    echo "Starting splash (streaming to terminal)..."
    splash serve \
        --language-only \
        --max-cache-disk "$MAX_CACHE_DISK" \
        --max-context "$MAX_CONTEXT" \
        --idle-release "$IDLE_RELEASE" \
        --model "$MODEL" \
        "$@" </dev/null &
else
    LOGFILE="$SCRIPT_DIR/splash.log"
    echo "Starting splash (logs: $LOGFILE)"
    { splash serve \
        --language-only \
        --max-cache-disk "$MAX_CACHE_DISK" \
        --max-context "$MAX_CONTEXT" \
        --idle-release "$IDLE_RELEASE" \
        --model "$MODEL" \
        "$@" </dev/null >>"$LOGFILE" 2>&1 & }
fi
SPINNER=$!
disown "$SPINNER" 2>/dev/null || true
sleep 3

if ! kill -0 "$SPINNER" 2>/dev/null; then
    echo "Warning: splash serve exited quickly; may not be ready" >&2
fi

# Reclaim the terminal only when stdin is not already one. Re-opening
# /dev/tty while it is already stdin makes the TUI agents (opencode,
# claude, hermes) ignore typed input.
if [ -e /dev/tty ] && [ ! -t 0 ]; then
    exec </dev/tty
fi
printf "\nSplash is starting on port %s.\n\n" "$PORT"

# Agent selection menu
select_agent() {
    printf "Select agent:\n"
    printf "  1) opencode\n"
    printf "  2) hermes\n"
    printf "  3) claude\n"
    printf "  4) browser (web chat UI)\n"
    printf "  5) none\n"
    printf "Choice [1-5]: "
    read -r agent_choice
    case "$agent_choice" in
        1) AGENT="opencode" ;;
        2) AGENT="hermes" ;;
        3) AGENT="claude" ;;
        4) AGENT="browser" ;;
        5|*) AGENT="none" ;;
    esac
}

# Use CLI value if set, otherwise show menu
if [ "$AGENT_SET" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ]; then
    [ -z "$AGENT" ] && AGENT="none"
else
    select_agent
fi

# Remember the agent choice for next time
save_config

if [ "$AGENT" != "none" ]; then
    case "$AGENT" in
        browser)
            wait_for_server || exit 1
            echo "Opening chat UI in browser..."
            if command -v open >/dev/null 2>&1; then
                open "http://localhost:$PORT"
            elif command -v xdg-open >/dev/null 2>&1; then
                xdg-open "http://localhost:$PORT"
            elif command -v cygstart >/dev/null 2>&1; then
                cygstart "http://localhost:$PORT"
            else
                echo "Cannot determine browser opener; visit: http://localhost:$PORT" >&2
            fi
            echo "Splash running in background (PID $SPINNER)."
            echo "Use ctrl+Z to suspend or kill $SPINNER to stop."
            wait "$SPINNER"
            ;;
        *)
            wait_for_server || exit 1
            echo "Launching splash $AGENT..."
            if [ "$PORT" != "$DEFAULT_PORT" ]; then
                exec splash "$AGENT" --port "$PORT"
            else
                exec splash "$AGENT"
            fi
            ;;
    esac
else
    echo "No agent selected. Splash running in background (PID $SPINNER)."
    echo "Use ctrl+Z to suspend or kill $SPINNER to stop."
    wait "$SPINNER"
fi
