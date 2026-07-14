# Security Policy

## Scope

This widget deliberately has a minimal security surface:

- It never reads or writes credential files.
- Its only external interaction is spawning `codex app-server` (part of
  Codex CLI, already installed and trusted by the user) and exchanging
  JSON-RPC messages with it over stdio.
- It makes no network connections of its own and collects no data.

## Reporting a vulnerability

If you find a security issue — for example, a way the widget could leak
account information, execute unintended commands, or be abused by another
process — please open a GitHub security advisory on this repository
(Security tab → "Report a vulnerability"), or open a regular issue if the
problem is not sensitive.

Please include the macOS and Codex CLI versions you tested against.
