# Troubleshooting

Gather evidence before changing anything. The commands in
[evidence commands](#evidence-commands) are read-only unless marked otherwise.

## Symptom lookup

| Symptom | Likely cause and fix |
| --- | --- |
| DNS times out over the tailnet and nothing reaches the query log | [Pi-hole listening mode rejects the Tailscale source](pihole-configuration.md#critical-interface-listening-behavior) |
| Queries appear in the log but nothing is blocked | [The client uses another resolver](#another-vpn-or-dns-profile-takes-precedence) or Tailscale DNS override is disabled |
| Wi-Fi works but cellular fails | [The iPhone tunnel is suspended](#iphone-vpn-disconnected-or-suspended) or Private Relay interferes |
| It worked before and stopped without a configuration change | [The node key expired or the device was removed](#tailscale-key-expired-or-device-removed) |
| Resolution is intermittent | [The upstream resolver is failing](#upstream-dns-unavailable) or the tailnet is relaying over a constrained path |
| Pi-hole resolves for itself but not for clients | [Listening, firewall, or grants block the client path](#host-firewall-denies-dns) |
| UDP works but TCP fails | [The firewall or grant permits only one DNS protocol](#tailscale-access-policy-denies-dns) |
| One device works and another does not | [Per-device DNS acceptance or an additive access rule differs](#tailscale-access-policy-denies-dns) |
| A blocked domain still resolves | [Cache, application DoH, or an inactive list bypasses Pi-hole](#another-vpn-or-dns-profile-takes-precedence) |
| LAN clients lost DNS after the listening-mode change | [`SINGLE` or `BIND` selected only `tailscale0`](pihole-configuration.md#critical-interface-listening-behavior) |
| The phone has no DNS while Tailscale still shows connected | [Pi-hole, FTL, home Internet, or upstream DNS is unavailable](#failure-modes) |
| A captive portal will not open | [The portal needs connectivity before the tunnel can carry DNS](#captive-portal-blocks-initial-connectivity) |

## Failure boundary

When Tailscale is connected, DNS override is enabled, and Pi-hole is
unavailable, system DNS usually fails until Pi-hole or the DNS configuration is
restored. When Tailscale disconnects, the device usually returns to local or
carrier DNS, which restores resolution but bypasses Pi-hole filtering.
Applications with independent DNS, including DNS over HTTPS, can behave
differently.

## Failure modes

### Pi-hole server powered off

- **Symptoms:** All clients assigned only this resolver time out. The host does
  not answer Tailscale or DNS checks.
- **Expected behavior:** Connected clients retain the assigned resolver but
  cannot use it.
- **Detection:** Check Tailscale device status, host power, and Layer 1 from
  [testing](testing.md#layer-1-server-health).
- **Recovery:** Restore host power. If that is not quick, disable Tailscale DNS
  on one client, then use the staged [rollback](rollback.md).
- **Rollback:** Restore the prior nameserver configuration.
- **Residual risk:** One server remains a single point of failure.

### Pi-hole FTL stopped

- **Symptoms:** The host is reachable but TCP and UDP 53 fail.
- **Expected behavior:** Tailscale stays connected while DNS fails.
- **Detection:** `systemctl status pihole-FTL` and `sudo ./scripts/health-check.sh`.
- **Recovery:** Review the FTL journal, correct the cause, then use the normal
  service start procedure approved for the host.
- **Rollback:** Restore the previous Pi-hole configuration or backup.
- **Residual risk:** Restarting without correcting storage or configuration
  damage can produce another outage.

### Tailscale disconnected on the Pi-hole host

- **Symptoms:** LAN DNS may work while the Tailscale address and remote DNS do
  not.
- **Expected behavior:** Remote devices cannot reach Pi-hole through the tunnel.
- **Detection:** `tailscale status --json` and `systemctl status tailscaled`.
- **Recovery:** Restore the daemon or enrollment. Do not paste an auth key into
  commands, files, or logs.
- **Rollback:** Restore the previous Tailscale DNS settings.
- **Residual risk:** Local Pi-hole health does not prove tailnet reachability.

### Tailscale disconnected on the iPhone

- **Symptoms:** Internet access can continue, but Pi-hole sees no new phone
  queries.
- **Expected behavior:** iOS usually returns to Wi-Fi or carrier DNS, bypassing
  Pi-hole.
- **Detection:** Check the Tailscale connection and correlate a fresh query.
- **Recovery:** Reconnect Tailscale and review the On Demand configuration.
- **Rollback:** Leave Tailscale disconnected only as a temporary client-side DNS
  recovery.
- **Residual risk:** Browsing during the disconnect is not filtered by Pi-hole.

### Home Internet unavailable

- **Symptoms:** The Pi-hole host can be online locally while remote name
  resolution and Internet access fail.
- **Expected behavior:** A home-hosted resolver cannot reach its upstream DNS.
- **Detection:** Compare LAN reachability, Tailscale status, and direct upstream
  resolution from the host.
- **Recovery:** Restore the home uplink or opt one client out of Tailscale DNS.
- **Rollback:** Restore the prior external resolver.
- **Residual risk:** DNS may recover before all home services stabilize.

### Upstream DNS unavailable

- **Symptoms:** Pi-hole receives queries but permitted domains time out or
  return upstream errors.
- **Expected behavior:** Cached answers may work while uncached names fail.
- **Detection:** Check Pi-hole logs and query the configured upstream from the
  Pi-hole host.
- **Recovery:** Restore or replace the failing upstream through an approved
  Pi-hole configuration change.
- **Rollback:** Restore the previous upstream set.
- **Residual risk:** Multiple upstreams can mask intermittent failures.

### Tailscale key expired or device removed

- **Symptoms:** The device loses tailnet access without a Pi-hole configuration
  change.
- **Expected behavior:** DNS through the removed or expired node stops.
- **Detection:** Inspect `tailscale status --json` and the Admin Console device
  state. The health check warns 14 days before server key expiry by default.
- **Recovery:** Reauthenticate or reapprove according to tailnet policy.
- **Rollback:** Temporarily restore the previous DNS path.
- **Residual risk:** Disabling expiry improves availability but weakens the
  response to stale credentials. This project does not automate that choice.

### Tailscale access policy denies DNS

- **Symptoms:** Tailscale is connected, but UDP or TCP DNS fails for selected
  identities.
- **Expected behavior:** Denied traffic never reaches Pi-hole.
- **Detection:** Run both protocol tests, policy tests, and review all additive
  grants and legacy ACLs.
- **Recovery:** Correct the narrow policy rule and rerun policy tests.
- **Rollback:** Restore the last known-good policy in the Admin Console.
- **Residual risk:** A broad additive rule can silently make policy too open.

### Host firewall denies DNS

- **Symptoms:** The service listens correctly, but remote DNS times out.
- **Expected behavior:** Packets are dropped before FTL handles them.
- **Detection:** Inspect the active ruleset and run TCP and UDP direct tests.
- **Recovery:** Apply the minimal `tailscale0` rules documented in
  [Pi-hole configuration](pihole-configuration.md#host-firewall).
- **Rollback:** Restore the captured ruleset.
- **Residual risk:** Another firewall manager can overwrite manual rules.

### iPhone VPN disconnected or suspended

- **Symptoms:** Filtering disappears after sleep, network changes, or background
  operation.
- **Expected behavior:** Without the tunnel, the phone uses another resolver.
- **Detection:** Check connection state and correlate a fresh query after wake.
- **Recovery:** Review On Demand and background behavior in
  [iOS configuration](ios-configuration.md).
- **Rollback:** Remove the On Demand change if it disrupts another required VPN.
- **Residual risk:** iOS controls background lifecycle and can delay reconnection.

### Another VPN or DNS profile takes precedence

- **Symptoms:** Tailscale is connected but queries do not reach Pi-hole, or only
  some applications bypass it.
- **Expected behavior:** iOS generally cannot run two packet-tunnel VPNs at once;
  DNS profiles and application DoH can also select another path.
- **Detection:** Disable one competing profile at a time during an approved test
  and correlate fresh queries.
- **Recovery:** Choose which VPN or resolver must own the traffic path.
- **Rollback:** Restore the original profile.
- **Residual risk:** Application-level encrypted DNS can remain outside system
  resolver control.

### Captive portal blocks initial connectivity

- **Symptoms:** Public Wi-Fi connects but neither the sign-in page nor DNS works.
- **Expected behavior:** The network may require portal authentication before
  Tailscale can establish a usable path.
- **Detection:** Temporarily disconnect Tailscale and open a plain HTTP site to
  trigger the owned network's portal.
- **Recovery:** Complete portal sign-in, reconnect Tailscale, and retest.
- **Rollback:** Forget the Wi-Fi network if its terms or security are unsuitable.
- **Residual risk:** Some portals disrupt VPN traffic after authentication.

## Evidence commands

These are read-only:

```bash
date --iso-8601=seconds
tailscale version
tailscale status --json
pihole-FTL --version
systemctl status tailscaled --no-pager
systemctl status pihole-FTL --no-pager
ss -H -lun 'sport = :53'
ss -H -ltn 'sport = :53'
sudo nft list ruleset
sudo ufw status verbose
dig @<PIHOLE_TAILSCALE_IP> <KNOWN_ALLOWED_DOMAIN>
dig +tcp @<PIHOLE_TAILSCALE_IP> <KNOWN_ALLOWED_DOMAIN>
journalctl -u tailscaled --since '15 minutes ago'
journalctl -u pihole-FTL --since '15 minutes ago'
```

The `sudo` evidence commands can expose private addresses and policy details.
Store raw output only under `evidence/`. Commands such as `systemctl restart`,
`tailscale up`, firewall changes, and Pi-hole setting changes modify state and
are deliberately excluded from this evidence set.
