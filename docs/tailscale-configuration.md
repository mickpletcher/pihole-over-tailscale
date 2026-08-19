# Tailscale configuration

## Install Tailscale on the Pi-hole host

The primary baseline uses the official Debian-family package path. The helper
script downloads the official convenience installer to a temporary file for
reviewable execution instead of piping it directly into a shell.

```bash
./scripts/install-tailscale.sh
sudo ./scripts/install-tailscale.sh --apply
```

Manual official convenience command:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Piping downloaded code into a shell executes remote code. Prefer the helper's
download-then-execute behavior or inspect the installer before running it.

Enroll interactively:

```bash
sudo tailscale up --accept-dns=false
tailscale ip -4
tailscale status
tailscale version
```

After enrollment, keep the existing state and change only the DNS preference:

```bash
sudo tailscale set --accept-dns=false
```

This prevents the DNS server host from depending on the tailnet DNS settings it
serves. Depending on the Linux resolver and Pi-hole upstream configuration,
accepting those settings can create a self-dependency or resolution loop.

## Network ports

Tailscale normally requires no inbound port forwarding. On restricted egress
networks, allow TCP destination port 443, UDP destination port 3478, and UDP
from the client's configured source port, which defaults to 41641, to arbitrary
destinations. A blocked direct path falls back to an encrypted relay and may
have higher latency.

## Node key expiration

Do not disable key expiration automatically. Monitor the current key expiry and
warn before it interrupts DNS service. `scripts/health-check.sh` warns at 14
days by default.

For an intentionally unattended server, a tailnet administrator may decide to
disable expiry manually after evaluating physical security, disk protection,
host patching, revocation procedures, and the consequence of a stolen node key.
Record that decision outside this repository. Never embed keys or session data.

## Access policy

Capture the existing policy before editing it. Tailscale grants and ACLs are
additive. A narrow DNS grant does not remove access granted by an existing broad
rule, including the default allow-all policy.

This HuJSON is a template. Replace both identity placeholders in the Admin
Console before validation. Do not apply it unchanged:

```jsonc
{
  "tagOwners": {
    "tag:pihole-dns": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["<AUTHORIZED_DNS_USER>"],
      "dst": ["tag:pihole-dns"],
      "ip": ["udp:53", "tcp:53"]
    }
  ],
  "tests": [
    {
      "src": "<AUTHORIZED_DNS_USER>",
      "proto": "udp",
      "accept": ["tag:pihole-dns:53"]
    },
    {
      "src": "<AUTHORIZED_DNS_USER>",
      "proto": "tcp",
      "accept": ["tag:pihole-dns:53"]
    },
    {
      "src": "<UNAUTHORIZED_DNS_USER>",
      "proto": "udp",
      "deny": ["tag:pihole-dns:53"]
    },
    {
      "src": "<UNAUTHORIZED_DNS_USER>",
      "proto": "tcp",
      "deny": ["tag:pihole-dns:53"]
    }
  ]
}
```

Assign `tag:pihole-dns` only to the Pi-hole device. Audit all overlapping grants
and ACLs for the destination before claiming least privilege. The policy does
not grant SSH, the web interface, or any non-DNS port.

The Admin Console validates policy syntax and its embedded tests when saved.
Testing a genuinely unauthorized identity requires a separately approved test
identity and remains `PENDING` without that authorization.

## Tailnet DNS

This is a tailnet-wide change for every connected device that accepts Tailscale
DNS settings.

Before enabling override:

1. Inventory clients that accept Tailscale DNS.
2. Confirm the Pi-hole host uses `accept-dns=false`.
3. Confirm intended clients can reach Pi-hole on TCP and UDP port 53.
4. Capture the current DNS page configuration.
5. Prepare rollback by keeping the DNS page open in an independent session.

In the Tailscale Admin Console:

1. Open **DNS**.
2. Under **Nameservers**, select **Add nameserver**, then **Custom**.
3. Enter `<PIHOLE_TAILSCALE_IP>` as a global nameserver.
4. Keep MagicDNS enabled unless a verified incompatibility exists.
5. Enable **Override DNS servers** only after preflight succeeds.
6. Validate one noncritical client before broader testing.

If isolation is required, use a separate test tailnet. Temporarily opting all
other devices out of Tailscale DNS is also a tailnet-wide loss of filtering and
requires approval.

Clients that disconnect from Tailscale return to their operating-system or
local-network DNS. If the only Pi-hole is unavailable, clients accepting the
override generally lose system DNS until Pi-hole returns or override is removed.
Applications with independent encrypted DNS can behave differently.

Multiple global nameservers are not ordered primary and secondary. Tailscale or
the operating system can query in parallel or reorder them. Never add an
unfiltered public resolver as backup.

When an Exit Node is later selected, review the nameserver option that controls
whether this Pi-hole remains active for Exit Node clients.

### Split DNS alternative

A restricted nameserver sends only specified domains to Pi-hole. Its blast
radius is smaller and failures affect fewer names, but it does not provide the
all-domain filtering this project exists to deliver.

## Tailnet rollback

1. Disable **Override DNS servers**.
2. Restore the captured nameserver entries and MagicDNS state.
3. Restore the previous access policy.
4. On the Pi-hole host, keep `accept-dns=false` unless a separate design says
   otherwise.
5. Verify one client uses its normal local resolver again.
