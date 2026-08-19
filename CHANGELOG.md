# Changelog

All notable repository changes are recorded here.

## Unreleased

### Added

- End-to-end Pi-hole over Tailscale documentation.
- Read-only DNS verification and server health scripts.
- Gated Tailscale installation, Pi-hole backup, and Pi-hole restore scripts.
- A hardened systemd health-check timer.
- Safe mocked tests and a pinned CI workflow.

### Security

- Pi-hole restore requires FTL 6.7 or newer.
- Private evidence, logs, and backup archives are excluded from Git.
- DNS access is scoped to TCP and UDP port 53 over intended LAN and Tailscale
  paths.
