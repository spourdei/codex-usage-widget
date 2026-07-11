#!/bin/bash
# Codex Usage Widget — one-command installer.
# Usage: ./install.sh   (or double-click after: chmod +x install.sh)
set -euo pipefail

cd "$(dirname "$0")"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m! %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1"; exit 1; }

bold "Codex Usage Widget installer"
echo

# 1. Swift compiler (ships with Xcode Command Line Tools).
if ! xcode-select -p >/dev/null 2>&1; then
  warn "Apple's developer tools are missing. A dialog will pop up — click Install, then run this script again."
  xcode-select --install >/dev/null 2>&1 || true
  exit 1
fi
ok "Developer tools found"

# 2. Codex CLI.
CODEX="$(command -v codex || true)"
if [ -z "$CODEX" ]; then
  for c in "$HOME/.local/bin/codex" /opt/homebrew/bin/codex /usr/local/bin/codex; do
    [ -x "$c" ] && CODEX="$c" && break
  done
fi
if [ -z "$CODEX" ]; then
  fail "Codex CLI is not installed. Install it first: https://developers.openai.com/codex/cli/ — then run this script again."
fi
ok "Codex CLI found ($CODEX)"

# 3. Logged in? (auth.json existence is a cheap, read-only heuristic)
if [ ! -f "$HOME/.codex/auth.json" ]; then
  warn "You don't appear to be logged in to Codex."
  echo "  Opening login now — follow the browser prompts, then re-run this script."
  "$CODEX" login
  exit 1
fi
ok "Codex login detected"

# 4. Build + install + start at login.
bold "Building and installing…"
make install
echo
ok "All done! The widget is now on your screen (top-left) and will start automatically at login."
echo
echo "  Move it:    drag it anywhere"
echo "  Resize it:  drag the bottom-right corner"
echo "  Quit it:    right-click the widget"
echo "  Remove it:  run ./uninstall.sh"
