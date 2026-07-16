# Codex Usage Widget

If you've ever used Codex, you understand how annoying and difficult
it is to keep clicking your avatar → limits, just to see how many more
prompts you're allowed until you gotta use a reset token... or count the days till tuesday

This widget puts the number on your screen instead. Always on top, shows the remaining % and the reset date.

<img width="610" height="256" alt="Screenshot 2026-07-15 at 9 42 33 PM" src="https://github.com/user-attachments/assets/c6afe9d5-c96c-4630-9211-b3c3b99c6794" />

## Setup (2 minutes)

You need [Codex CLI](https://developers.openai.com/codex/cli/) installed and
logged in. If you already use Codex in your terminal, you're set.

1. Download this project (green **Code** button → **Download ZIP**, unpack it)

2. Open Terminal and run:

   ```sh
   cd ~/Downloads/codex-usage-widget* && ./install.sh
   ```

Done. The widget appears top-left and starts automatically at login. The
installer checks prerequisites and tells you how to fix anything missing.

## Everyday use

| Action    | How                             |
|-----------|---------------------------------|
| Move      | drag the widget anywhere        |
| Resize    | drag the bottom-right corner    |
| Refresh   | right-click → Refresh Now       |
| Quit      | right-click → Quit Codex Usage  |
| Remove    | run `./uninstall.sh`            |

Refreshes every 5 minutes. Remembers its size and position.

## How it works

It launches `codex app-server` (the official JSON-RPC interface in Codex CLI)
and calls `account/rateLimits/read`. That's it. No credential access, no
undocumented endpoints, no analytics. The whole app is one Swift file under
500 lines: [CodexUsage.swift](CodexUsage.swift) — read it.

## For developers

```sh
make build      # compile
make run        # compile and run in foreground
make install    # install + start at login
make uninstall  # remove everything
```

Codex binary somewhere unusual? `CODEX_BIN=/path/to/codex ~/.local/bin/CodexUsage`

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Notes

Unofficial community tool, not affiliated with OpenAI. Requires macOS 13+.
The app-server protocol is marked experimental upstream; if it changes,
update Codex CLI and this widget.

## License

MIT — see [LICENSE](LICENSE).
