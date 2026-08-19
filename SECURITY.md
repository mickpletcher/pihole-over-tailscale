# Security policy

## Supported versions

The documentation and scripts target Pi-hole v6 with FTL 6.7 or newer, native
systemd-based Debian-family hosts, and a current stable Tailscale client.

## Reporting a vulnerability

Do not include credentials, tailnet names, private addresses, query history,
backup archives, or private topology in a public issue. Report sensitive issues
privately to the repository owner using GitHub's private vulnerability reporting
feature when it is enabled.

## Operational boundary

This repository does not make live changes by itself. Installation, firewall,
Pi-hole, tailnet, phone, and restore changes require explicit approval in the
environment where they are performed. See [Security](docs/security.md).
