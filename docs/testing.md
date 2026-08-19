# Testing

Treat each layer as separate evidence. Passing a lower layer does not prove a
higher layer passed. Replace every placeholder with a value from
[prerequisites](prerequisites.md#placeholders) before running a live test.

## Layer 1: server health

Run the complete check set defined by [`health-check.sh`](../scripts/health-check.sh):

```bash
sudo ./scripts/health-check.sh --server <PIHOLE_TAILSCALE_IP>
```

Exit `0` is a Layer 1 pass. Exit `1` means one or more warnings. Exit `2` means
at least one failure. This is a local server check. It does not prove that a
remote client can reach or automatically use Pi-hole.

## Layer 2: remote tailnet DNS path

Run these commands from a second authorized tailnet device, not the Pi-hole
host:

```bash
dig @<PIHOLE_TAILSCALE_IP> <KNOWN_ALLOWED_DOMAIN>
dig +tcp @<PIHOLE_TAILSCALE_IP> <KNOWN_ALLOWED_DOMAIN>
./scripts/verify-dns.sh <PIHOLE_TAILSCALE_IP> \
  --allowed-domain <KNOWN_ALLOWED_DOMAIN> \
  --blocked-domain <KNOWN_BLOCKED_DOMAIN>
```

When `dig` is unavailable, use this direct-server alternative:

```text
nslookup <KNOWN_ALLOWED_DOMAIN> <PIHOLE_TAILSCALE_IP>
```

Passing proves direct TCP and UDP DNS reachability. It does not prove the
operating system is using Tailscale DNS automatically.

## Layer 3: client system resolver

Do not specify a DNS server in this layer.

| Client | Native test command |
| --- | --- |
| Linux with systemd-resolved | `resolvectl query <KNOWN_ALLOWED_DOMAIN>` |
| macOS | `dscacheutil -q host -a name <KNOWN_ALLOWED_DOMAIN>` |
| Windows 11 PowerShell | `Resolve-DnsName <KNOWN_ALLOWED_DOMAIN>` |
| iPhone or iPad | Open a fresh permitted-domain URL in Safari; iOS has no built-in command-line resolver test |

Immediately query `<KNOWN_BLOCKED_DOMAIN>` the same way. In the Pi-hole query
log, verify the permitted and blocked queries, the expected Tailscale client,
and timestamps inside the test window. Use fresh names or clear the applicable
client cache before repeating a test. A blocked response can be `NXDOMAIN`,
`NODATA`, zero addresses, or another response configured in Pi-hole.

## Layer 4: iPhone Wi-Fi

1. Connect the iPhone to Wi-Fi and confirm Tailscale is connected.
2. Open a fresh URL under `<KNOWN_ALLOWED_DOMAIN>` in Safari.
3. Correlate the new query, expected client, and timestamp in Pi-hole.
4. Query `<KNOWN_BLOCKED_DOMAIN>` and confirm the configured blocking response.

## Layer 5: iPhone cellular

1. Disable Wi-Fi.
2. Confirm cellular data is active.
3. Confirm Tailscale is connected.
4. Generate a fresh permitted-domain query.
5. Generate a fresh query for `<KNOWN_BLOCKED_DOMAIN>`.
6. Confirm both queries appear in Pi-hole under the expected Tailscale client.
7. Confirm the permitted domain resolves and the denylisted domain is blocked.
8. Confirm no Exit Node is selected.

## Layer 6: negative security tests

Live negative tests require explicit approval. Otherwise record `PENDING`.

- From an unauthorized identity you control, confirm TCP and UDP 53 cannot be
  reached. Do not test an account or device you do not control.
- From a public network you control, use the owned host's public IPv4 or IPv6
  address and the direct DNS commands in
  [host firewall verification](pihole-configuration.md#positive-and-negative-verification).
- Confirm the Pi-hole web interface is not reachable through an unintended
  public or tailnet path.
- Review the whole Tailscale policy for an additive broad rule that bypasses
  the narrow DNS grant.

Do not use third-party scanning services.

## Layer 7: failure and rollback

Do not stop live DNS, alter tailnet DNS, or disconnect managed clients without
explicit approval. When approval is absent, record `PENDING` and use this manual
procedure during an approved maintenance window:

1. Record the starting resolver path and complete Layers 1 through 5.
2. Test one condition at a time: Pi-hole outage, Tailscale disconnect, upstream
   resolver outage, and the rollback path.
3. For each condition, record observed client behavior. Do not substitute the
   expected behavior from [troubleshooting](troubleshooting.md#failure-modes).
4. Restore the changed component before testing the next condition.
5. Run the applicable lower and higher layers again.

## Evidence record

Record the date, component versions, network path, result, and evidence type:
static, mocked, local integration, or live end-to-end. Store sensitive raw
evidence under `evidence/`, which Git ignores. Commit only a sanitized summary
when useful. Never commit screenshots containing tailnet names, identities,
private addresses, or query history.
