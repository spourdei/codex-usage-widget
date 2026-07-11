#!/bin/bash
# Codex Usage Widget — uninstaller.
set -euo pipefail
cd "$(dirname "$0")"
make uninstall
printf '\033[32m✓ Widget removed. It will no longer start at login.\033[0m\n'
