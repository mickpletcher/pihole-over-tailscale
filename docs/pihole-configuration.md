# Pi-hole configuration

## Before changing Pi-hole

Run on the Pi-hole host:

```bash
pihole version
pihole-FTL --version
sudo ./scripts/backup-config.sh
mkdir -p evidence
chmod 700 evidence
sudo pihole-FTL --config dns.listeningMode > evidence/listening-before.txt
```

Record the active firewall manager without changing it:

```bash
sudo ufw status verbose
sudo nft list ruleset
systemctl is-active firewalld
```

Use the tool that already manages the host. Do not stack UFW, raw nftables, and
firewalld rules without understanding their interaction.

## Critical interface listening behavior

Pi-hole v6 uses `dns.listeningMode` and `dns.interface`. The current modes are:

| Mode | Behavior | Use here |
| --- | --- | --- |
| `LOCAL` | Accept only local-subnet requests | Test first; default and safest |
| `SINGLE` | Accept all origins on one selected interface | Tailscale-only dedicated server |
| `BIND` | Bind only selected interfaces | Special multi-resolver hosts only |
| `ALL` | Accept all origins on all interfaces | Shared LAN and Tailscale fallback with firewalls |
| `NONE` | Supply no generated listening rule | Unsupported by this repository |

Remote Tailscale clients can be rejected under `LOCAL` because their source is
not necessarily classified as a directly connected local subnet. The symptom is
a DNS timeout with no matching Pi-hole query-log entry. Test before assuming.

Read the current setting:

```bash
sudo pihole-FTL --config dns.listeningMode
sudo pihole-FTL --config dns.interface
```

Test `LOCAL` from a remote authorized client before changing it. If it fails,
prepare the firewall and tailnet grant first, then set `ALL`:

```bash
sudo pihole-FTL --config dns.listeningMode ALL
```

The command changes `/etc/pihole/pihole.toml` through Pi-hole's supported
configuration interface. Roll back by setting the exact captured prior value.

Do not set `dns.interface` to `tailscale0` with `SINGLE` or `BIND` on a Pi-hole
that also serves LAN clients. That can remove LAN DNS. A `tailscale0`-only design
is valid only for a dedicated Tailscale-only Pi-hole.

## Verify listening sockets

Run separate exact checks for UDP and TCP port 53:

```bash
sudo ss -H -lun 'sport = :53'
sudo ss -H -ltn 'sport = :53'
```

Confirm each result is bound to `<PIHOLE_TAILSCALE_IP>` or an intentional
wildcard address. A wildcard listener is safe here only when the host firewall
restricts the reachable interfaces. Check for another local resolver occupying
port 53 before changing Pi-hole.

## Host firewall

Capture the complete current ruleset to `evidence/` before applying anything.
Keep an independent login open so a bad rule can be reverted.

The intended policy is:

- Allow TCP and UDP port 53 inbound on `tailscale0`.
- Preserve existing LAN DNS from `<LAN_SUBNET>` on `<LAN_INTERFACE>`.
- Deny TCP and UDP port 53 on `<PUBLIC_INTERFACE>`.
- Do not include SSH or the Pi-hole web interface in these DNS rules.

### UFW example

Review with `sudo ufw status numbered` before applying:

```bash
sudo ufw allow in on tailscale0 to any port 53 proto udp comment 'Pi-hole Tailscale DNS UDP'
sudo ufw allow in on tailscale0 to any port 53 proto tcp comment 'Pi-hole Tailscale DNS TCP'
sudo ufw allow in on <LAN_INTERFACE> from <LAN_SUBNET> to any port 53 proto udp comment 'Pi-hole LAN DNS UDP'
sudo ufw allow in on <LAN_INTERFACE> from <LAN_SUBNET> to any port 53 proto tcp comment 'Pi-hole LAN DNS TCP'
sudo ufw deny in on <PUBLIC_INTERFACE> to any port 53 proto udp comment 'Block public DNS UDP'
sudo ufw deny in on <PUBLIC_INTERFACE> to any port 53 proto tcp comment 'Block public DNS TCP'
sudo ufw status verbose
```

Rollback uses the numbered-rule form after reviewing it:

```bash
sudo ufw status numbered
sudo ufw delete <RULE_NUMBER>
```

Delete in descending number order because UFW renumbers after each deletion.

### nftables example

Do not paste a new base chain into an unknown ruleset. Inspect the active table,
chain, hook, priority, and persistence mechanism first. Adapt these scoped rule
expressions to the existing input chain:

```bash
iifname "tailscale0" udp dport 53 accept comment "Pi-hole Tailscale DNS UDP"
iifname "tailscale0" tcp dport 53 accept comment "Pi-hole Tailscale DNS TCP"
iifname "<LAN_INTERFACE>" ip saddr <LAN_SUBNET> udp dport 53 accept comment "Pi-hole LAN DNS UDP"
iifname "<LAN_INTERFACE>" ip saddr <LAN_SUBNET> tcp dport 53 accept comment "Pi-hole LAN DNS TCP"
iifname "<PUBLIC_INTERFACE>" udp dport 53 drop comment "Block public DNS UDP"
iifname "<PUBLIC_INTERFACE>" tcp dport 53 drop comment "Block public DNS TCP"
```

Use rule handles from `sudo nft -a list ruleset` for exact rollback. Save changes
only through the selected distribution's supported persistence mechanism.

## Positive and negative verification

From an authorized remote tailnet client:

```bash
dig @<PIHOLE_TAILSCALE_IP> <KNOWN_ALLOWED_DOMAIN>
dig +tcp @<PIHOLE_TAILSCALE_IP> <KNOWN_ALLOWED_DOMAIN>
```

From an existing LAN client, query its configured Pi-hole normally and confirm
the request appears in Pi-hole. Use `<LAN_DNS_CLIENT_IP>` only for correlation;
do not commit it.

From an external host you own and control, both commands must time out or be
refused:

```bash
dig @<PUBLIC_IP> <KNOWN_ALLOWED_DOMAIN>
dig +tcp @<PUBLIC_IP> <KNOWN_ALLOWED_DOMAIN>
```

Also verify that the Pi-hole web interface did not become reachable through a
new path. Do not use a third-party scanning service.

If either existing LAN DNS or authorized tailnet DNS fails after a change, use
[Immediate rollback](rollback.md#immediate-rollback).
