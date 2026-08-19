# Pi-hole over Tailscale

Status: In development

Live validation: PENDING

Use your home Pi-hole as the DNS filtering service for phones, laptops, and
other Tailscale-connected devices anywhere, including over cellular and public
Wi-Fi.

This repository documents a DNS-only deployment. Tailscale encrypts DNS traffic
between a client and Pi-hole. Ordinary web traffic does not pass through the
home network unless you separately select an Exit Node. Pi-hole's connection to
its upstream resolver is a separate trust boundary.

## Supported baseline

- Native Pi-hole v6 on a supported systemd-based Raspberry Pi OS or Debian host.
- Pi-hole FTL 6.7 or newer for automated restore.
- Tailscale in the same host network namespace as Pi-hole.
- A current stable Tailscale client.
- iOS 15 or newer with the current App Store Tailscale client.

Ubuntu can use the Debian-family installation path, but remains unverified until
it is included in the [tested-environment matrix](docs/prerequisites.md).
Containers, Kubernetes, NAS packages, and Pi-hole v5 are not supported by the
core scripts.

## Architecture

The phone sends DNS queries through its encrypted Tailscale path to Pi-hole.
Pi-hole then resolves allowed queries through its configured upstream resolver.
See [Architecture](docs/architecture.md) for the traffic paths, trust boundaries,
and single-Pi-hole failure behavior.

## Prerequisites

Read [Prerequisites](docs/prerequisites.md) before changing anything. You need
administrative access to the Pi-hole host and tailnet, an existing working
Pi-hole, and a known rollback path.

## Quick start

1. Read [Installation](docs/installation.md) end to end.
2. Create a private backup with `sudo ./scripts/backup-config.sh`.
3. Install Tailscale with `./scripts/install-tailscale.sh`, review the plan, then
   rerun it with `sudo ./scripts/install-tailscale.sh --apply` if needed.
4. Configure Pi-hole and its firewall using
   [Pi-hole configuration](docs/pihole-configuration.md).
5. Configure the Tailscale DNS server and grant using
   [Tailscale configuration](docs/tailscale-configuration.md).
6. Configure and test the phone using [iOS configuration](docs/ios-configuration.md).
7. Run the layered checks in [Testing](docs/testing.md).

Do not run documentation commands blindly. Back up first. Keep DNS port 53
closed to the public Internet. Changing Pi-hole listening behavior, host
firewall rules, or tailnet DNS can interrupt DNS for every dependent client.

## Validation and recovery

`scripts/verify-dns.sh` performs direct UDP and TCP DNS checks from an authorized
tailnet client. `scripts/health-check.sh` checks only server-side health; it does
not prove that an iPhone or another remote client works.

If DNS breaks, use [Immediate rollback](docs/rollback.md#immediate-rollback).
Symptom-first help is in [Troubleshooting](docs/troubleshooting.md).

## Advanced options

- [DNS-only versus Exit Node](docs/advanced/exit-node.md)
- [Subnet routing](docs/advanced/subnet-routing.md)
- [Multiple Pi-hole servers](docs/advanced/multiple-pihole-servers.md)
- [High availability](docs/advanced/high-availability.md)

The initial deployment deliberately remains single-server. Do not add an
unfiltered resolver as a fallback because resolver order is not guaranteed.
