# Prerequisites

Use this checklist before starting. If any required item is missing, stop before
changing Pi-hole, the firewall, or tailnet DNS.

## Supported baseline

The primary baseline is a native Pi-hole v6 installation with FTL 6.7 or newer
on a supported, systemd-based Raspberry Pi OS or Debian host. Tailscale runs in
the same network namespace. Ubuntu uses the same Debian-family package path but
is secondary until live-tested.

Check versions on the Pi-hole host:

```bash
pihole version
pihole-FTL --version
tailscale version
```

Pi-hole v5, containers, Kubernetes, NAS packages, non-systemd service layouts,
and separate Tailscale network namespaces are not supported by the core scripts.

## Required access

- Root or `sudo` access to the Pi-hole host.
- Tailnet Owner, Admin, Network admin, or another role permitted to change DNS
  and access policy.
- Physical or independent administrative access in case DNS or firewall changes
  interrupt remote access.
- An authorized iPhone running iOS 15 or newer and the current Tailscale app.
- A current private Pi-hole backup and tested rollback commands.

The Tailscale Personal plan is sufficient for a small personal deployment within
its current user and device limits. Verify current plan limits before relying on
them.

## Network requirements

Most Tailscale installations need no manually opened inbound port. Restricted
egress networks should allow:

| Direction | Protocol and port | Purpose |
| --- | --- | --- |
| Outbound destination | TCP 443 | Coordination and DERP HTTPS |
| Outbound source | UDP 41641 by default, to arbitrary destinations | Direct WireGuard paths |
| Outbound destination | UDP 3478 | STUN |

The UDP source port is configurable. If direct UDP cannot be established,
Tailscale can use an encrypted peer relay or DERP relay at lower performance.
No router port-forward or publicly exposed DNS listener is required.

## Runtime tools

| Tool | Used by | Debian-family package |
| --- | --- | --- |
| `dig` | DNS tests and health checks | `dnsutils` |
| `curl` | Installer download and restore API | `curl` |
| `jq` | Machine-readable Tailscale and Pi-hole API data | `jq` |
| `ss` | Exact TCP and UDP listener checks | `iproute2` |
| `systemctl` | Service state | `systemd` |
| `timeout` | Bounded network operations | `coreutils` |
| `git` and `realpath` | Backup path boundary checks | `git`, `coreutils` |
| `unzip` | Backup and restore integrity checks | `unzip` |
| `nslookup` | Limited direct-server fallback | `dnsutils` |

Install missing runtime tools on a Debian-family host only after approval:

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends curl dnsutils git iproute2 jq unzip
```

## Placeholders

Replace placeholders locally. Do not commit the resulting private values.

| Placeholder | Meaning | Format | Value source |
| --- | --- | --- | --- |
| `<PIHOLE_TAILSCALE_IP>` | Pi-hole Tailscale IPv4 address | Tailscale-assigned IPv4 address | `tailscale ip -4` on Pi-hole |
| `<KNOWN_BLOCKED_DOMAIN>` | Domain on the active denylist | Fully qualified domain | Your Pi-hole denylist |
| `<KNOWN_ALLOWED_DOMAIN>` | Domain expected to resolve | Fully qualified domain | A domain you control or `example.com` |
| `<COPYRIGHT_HOLDER>` | License holder | Name, no email | Repository owner |
| `<LAN_DNS_CLIENT_IP>` | Existing LAN test client | IPv4 or IPv6 | Your LAN inventory |
| `<LAN_INTERFACE>` | Pi-hole LAN interface | Linux interface name | `ip link` |
| `<LAN_SUBNET>` | Existing LAN client subnet | IPv4 or IPv6 CIDR | Router configuration |
| `<PUBLIC_INTERFACE>` | Internet-facing host interface | Linux interface name | `ip route` and host configuration |
| `<PUBLIC_IP>` | Public address under your control | IPv4 or IPv6 | Your router or provider |
| `<AUTHORIZED_DNS_USER>` | Identity allowed to use Pi-hole | Tailnet user selector | Tailnet identity inventory |
| `<UNAUTHORIZED_DNS_USER>` | Identity used for denial testing | Separate tailnet selector | Approved test identity |
| `<RULE_NUMBER>` | Number of a reviewed UFW rule selected for rollback | Positive integer | `sudo ufw status numbered` |

## Tested-environment matrix

| Component | Version | Platform | Status |
| --- | --- | --- | --- |
| Repository scripts | Current worktree | Windows 11, Git Bash 5.3.15, mocked tests | PASS, 2026-08-19 |
| Pi-hole | v6, FTL 6.7 or newer | Native Raspberry Pi OS or Debian | PENDING |
| Tailscale server | Current stable | Same host namespace | PENDING |
| Tailscale iOS | Current App Store build | iOS 15 or newer | PENDING |

Replace `PENDING` only with dated evidence from the actual environment.

## You do not need this if

- Filtering is required only on the home LAN.
- A managed DNS filtering service already meets the requirement.
- You cannot tolerate a single DNS server failure and are not ready to deploy
  two equivalently filtered servers.
- Another VPN must remain active on iOS at the same time.
