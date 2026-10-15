# splashControl

One POSIX-sh script, `start_splash.sh`, that ensures Homebrew + `splash`
(`incoai/tap/splash`) are installed/current and launches `splash serve`
with remembered settings, optionally followed by an agent. No build step,
no test suite, no lint/CI config. The only other tracked files are `README.md`,
`.envexample`, `.gitignore`, and a stale tracked `splash.log`.

## Verify changes

- There are no automated tests. Smoke-test manually.
- `sh -n start_splash.sh` is the minimum syntax check, but on macOS `/bin/sh`
  is bash 3.2, so it accepts bashisms. The script targets POSIX sh (on Linux
  `/bin/sh` is usually dash): check with `dash -n start_splash.sh` when
  available.
- Avoid slow/full runs while testing: `-s` skips `brew update`/`upgrade`,
  `-y -a none` skips prompts. A real run starts `splash serve` and loads a
  model, so it is not a cheap check.

## Editing constraints

- Keep it POSIX sh: no arrays, `[[ ]]`, `local`, or `source`. The code uses
  `case`, `printf`, and `read` throughout.
- The startup symlink loop follows `$0` (which may be the `splashctl` launcher)
  to find the real `SCRIPT_DIR` before locating `.env` and `splash.log`.
  Don't simplify it or invoking via the launcher breaks.
- The launcher must stay named `splashctl`: the script calls the real `splash`
  binary internally, so a link named `splash` would recurse forever.
- `.env` is hand-parsed, never sourced (values are never executed).

## Adding a remembered setting

Thread a new key through **all** of these, or it silently won't persist:
`load_config` (the `case "$key"`), `save_config` (the heredoc), the arg-parse
`while [ $# -gt 0 ]` loop, `usage()`, and `.envexample`. Format is `KEY=value`;
`MODEL_HISTORY` is a `;`-joined, most-recent-first list (model ids never contain
`;`). Override the config file path with `SPLASH_CONTROL_ENV`.

## Options

`--help` (and the README options table) is authoritative and kept in sync with
the arg parser. `-a browser` opens the web chat UI instead of a TUI agent, and
`--` forwards the rest to `splash serve` unparsed. When you add or change a
flag, update `usage()`, the README table, and `.envexample` too.

## Runtime gotchas

- Agents launch only after `wait_for_server` sees `/ready` return 200 (503
  while the model loads; the endpoint needs no API key). Default is no timeout;
  `-w SECONDS` bounds it, aborting early if `splash serve` exits.
- Port resolution: a `--port` in the forwarded args wins, then `SPLASH_PORT`,
  then 8000. The port is only passed to the agent when it isn't 8000.
- `stop_existing_splash` kills `pgrep -f "splash serve"` and anything holding
  the port (`lsof -i :$PORT -sTCP:LISTEN`); it prompts unless `-y`/`-k`.
- `/dev/tty` is reopened only when stdin isn't already a tty, so TUI agents
  (opencode/claude/hermes) don't ignore typed input.
- Without `-s`, every run does `brew update` + `brew upgrade` and may install
  Homebrew (sudo prompt).
- Default output goes to `splash.log` and is `tail -f`'d during startup;
  `--live` streams to the terminal instead.

## Git gotcha

`splash.log` is **tracked** even though `.gitignore` lists it (it was committed
before the ignore rule), so it shows as modified after every run. Don't assume
the ignore entry untracked it; leave it, or `git rm --cached splash.log`.
