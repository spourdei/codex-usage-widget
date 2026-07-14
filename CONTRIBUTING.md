# Contributing

This project is deliberately small: one Swift file, a Makefile, two shell
scripts. Please keep it that way.

## Ground rules

- **No new dependencies.** The whole point is `swiftc` + AppKit, nothing else.
- **Keep it transparent.** The widget must only talk to `codex app-server`
  (the official JSON-RPC interface). PRs that read credential files or call
  undocumented HTTP endpoints will be declined.
- **Keep it small.** New features should justify their lines of code.

## Developing

```sh
make run     # compile and run in the foreground (Ctrl+C to stop)
```

There is no test suite; verify changes by running the widget and exercising
the affected behavior (resize, right-click menu, login states, etc.).

Useful manual checks before opening a PR:

- `make build` compiles without warnings
- `./install.sh` succeeds on a machine where the widget is already installed
  (upgrade path) and after `./uninstall.sh` (fresh path)
- The widget handles all three states: logged in, logged out
  (`codex logout`), and codex missing (`CODEX_BIN=/nonexistent`)

## Reporting bugs

Open a GitHub issue and include:

- macOS version
- Codex CLI version (`codex --version`)
- What the widget displayed (the detail line at the bottom shows errors)
