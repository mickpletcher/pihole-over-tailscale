# Installation

Read every phase before starting. Host and tailnet changes require separate
approval. The repository build does not authorize them.

## Phase 1: Verify prerequisites

- Run on: Pi-hole host and Tailscale Admin Console.
- Privilege: Read-only shell access and tailnet read access.
- Time: About 5 minutes.
- End state: The versions, tools, authority, and rollback access in
  [Prerequisites](prerequisites.md) are confirmed.
- Reversible: No changes are made.

## Phase 2: Back up Pi-hole

- Run on: Pi-hole host.
- Privilege: Enough local access for `pihole-FTL --teleporter`.
- Time: About 2 minutes.
- End state: A private, integrity-checked archive exists outside the Git
  worktree.
- Reversible: The backup does not change Pi-hole. See
  [Restore](rollback.md#restore-a-teleporter-backup).

```bash
sudo ./scripts/backup-config.sh
```

## Phase 3: Capture current state

- Run on: Pi-hole host.
- Privilege: `sudo` for complete firewall state.
- Time: About 3 minutes.
- End state: Private captures exist only under gitignored `evidence/`.
- Reversible: Read-only.

```bash
mkdir -p evidence
chmod 700 evidence
sudo nft list ruleset > evidence/firewall-before.txt
sudo pihole-FTL --config dns.listeningMode > evidence/listening-before.txt
chmod 600 evidence/firewall-before.txt evidence/listening-before.txt
```

If UFW manages the host, also capture `sudo ufw status verbose`. Never commit
these files.

## Phase 4: Install and enroll Tailscale

- Run on: Pi-hole host.
- Privilege: Review as the current user; `sudo` only with `--apply`.
- Time: About 5 minutes plus interactive enrollment.
- End state: `tailscaled` is active and the host is enrolled with tailnet DNS
  acceptance disabled.
- Reversible: See [Remove Tailscale](rollback.md#remove-tailscale).

```bash
./scripts/install-tailscale.sh
sudo ./scripts/install-tailscale.sh --apply
sudo tailscale up --accept-dns=false
sudo tailscale set --accept-dns=false
```

The script never accepts an auth key and never automates login.

## Phase 5: Configure Pi-hole and the firewall

- Run on: Pi-hole host.
- Privilege: `sudo` and Pi-hole administration.
- Time: About 10 minutes.
- End state: Existing LAN DNS still works, and authorized tailnet clients can
  reach only TCP and UDP port 53.
- Reversible: Use [Immediate rollback](rollback.md#immediate-rollback).

Follow [Pi-hole configuration](pihole-configuration.md). Test the default
`LOCAL` listening mode first. Escalate to `ALL` only after scoped firewall rules
and tailnet policy are ready.

## Phase 6: Configure tailnet policy

- Run on: Tailscale Admin Console.
- Privilege: Tailnet policy administrator.
- Time: About 10 minutes.
- End state: The intended identities can reach TCP and UDP port 53 on Pi-hole,
  and no broad rule bypasses the restriction.
- Reversible: Restore the captured policy.

Use [Access policy](tailscale-configuration.md#access-policy). Policy changes are
tailnet-wide and require approval.

## Phase 7: Configure tailnet DNS

- Run on: Tailscale Admin Console.
- Privilege: Tailnet DNS administrator.
- Time: About 5 minutes.
- End state: `<PIHOLE_TAILSCALE_IP>` is the global nameserver and Override DNS
  servers is enabled only after preflight tests pass.
- Reversible: Disable Override DNS servers and restore the previous DNS entries.

Use [Tailnet DNS](tailscale-configuration.md#tailnet-dns). Keep MagicDNS enabled
unless a verified conflict requires otherwise.

## Phase 8: Configure iOS

- Run on: Authorized iPhone.
- Privilege: Device user or MDM administrator.
- Time: About 5 minutes.
- End state: Tailscale is connected and accepts tailnet DNS.
- Reversible: Disconnect Tailscale or opt out of Tailscale DNS.

Follow [iOS configuration](ios-configuration.md).

## Phase 9: Validate

- Run on: Pi-hole host, a second tailnet client, and the iPhone.
- Privilege: Read-only, except an approved negative identity test.
- Time: About 15 minutes.
- End state: Every completed layer has dated evidence; unavailable live layers
  remain `PENDING`.
- Reversible: Tests are read-only unless explicitly marked otherwise.

Follow [Testing](testing.md). A passing host health check does not prove remote
or iPhone behavior.

## Phase 10: Schedule health checks

- Run on: Pi-hole host.
- Privilege: `sudo` to install systemd units.
- Time: About 5 minutes.
- End state: The timer is enabled and one firing has been verified.
- Reversible: See [Remove scheduled checks](maintenance.md#remove-the-timer).

Follow [Maintenance](maintenance.md). No repository script installs the timer
implicitly.
