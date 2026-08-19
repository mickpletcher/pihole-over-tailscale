# Deployment Security

Never expose Pi-hole UDP or TCP port 53 directly to the public Internet over
IPv4 or IPv6. Tailscale encrypts the path between enrolled nodes. It does not
make an unnecessarily public listener safe.

## Layered controls

Use all four controls:

1. A narrow Tailscale grant for authorized identities and both DNS protocols.
2. Host firewall rules scoped to `tailscale0`.
3. Router rules that do not forward public DNS traffic to Pi-hole.
4. A Pi-hole listening mode selected for the actual interfaces.

The exact host procedure is in
[Pi-hole configuration](pihole-configuration.md#host-firewall).
Rules in Tailscale policies are additive. A broad grant or legacy ACL elsewhere
can bypass a narrow rule even when the narrow rule is correct.

## Least-privilege grant

Replace all placeholders. Keep the source narrower than all tailnet members
unless every member is intentionally authorized.

```json
{
  "grants": [
    {
      "src": ["<AUTHORIZED_DNS_USER>"],
      "dst": ["<PIHOLE_TAILSCALE_IP>"],
      "ip": ["udp:53", "tcp:53"]
    }
  ]
}
```

Use Tailscale policy tests for both protocols and for an unauthorized identity.
Do not treat the example as the whole policy. Merge it into the existing policy
and review every additive rule.

## Identity and device response

- Require strong identity-provider authentication and multi-factor
  authentication where available.
- Use device approval when the administrative burden is acceptable.
- Remove stale devices. Revoke a lost device promptly, then review recent Pi-hole
  queries and tailnet activity without publishing the data.
- Never place auth keys, node keys, API tokens, or Tailscale state in this
  repository, shell history, evidence, or support messages.
- The server node key can expire and cause a DNS outage. Disabling expiry reduces
  that availability risk but lets a stolen node identity remain useful longer.
  This repository warns before expiry and leaves the decision to the owner.

## Host and Pi-hole

- Keep the supported operating system, Pi-hole, and Tailscale patched.
- Require Pi-hole administrator authentication and do not expose its web
  interface publicly. Scope administrative access separately from DNS access.
- Harden SSH with keys, restricted users, and the smallest reachable network
  scope. Do not assume Tailscale enrollment replaces host authentication.
- Review listener and firewall state after upgrades.
- Treat a compromised Pi-hole host as a tailnet and DNS incident. Disconnect or
  remove the node, restore from known-good media or configuration, rotate
  affected credentials, review policy, and validate every layer before reuse.

## Logs, backups, and secrets

Pi-hole query data can reveal browsing behavior. Use short retention that meets
the operational need, restrict file and dashboard access, and avoid exporting
raw logs. `evidence/` is local and gitignored, but it is still sensitive.

Backups contain private configuration and browsing-related data. Keep them
outside the repository with directory mode `0700` and file mode `0600`. Encrypt
secure transfers and remove obsolete archives according to the chosen retention
policy. The backup wrapper does not capture Tailscale node state.

Use interactive secret entry or an approved secret manager. Do not pass secrets
as command-line arguments, environment variables, repository values, logs, or
screenshots.

## Resolver privacy and bypasses

Tailscale encrypts DNS traffic to Pi-hole. Traffic from Pi-hole to its upstream
resolver has only the protection provided by that upstream protocol. Select an
upstream based on the required privacy, reliability, and trust properties.

Applications can use independent DNS over HTTPS or a built-in resolver and
bypass the operating system resolver. Pi-hole cannot filter a query it never
receives. Apple Private Relay, another VPN, or a managed DNS profile can also
change the path.

## Availability

A single Pi-hole assigned as the tailnet global resolver is a single point of
DNS failure while clients remain connected and accept the override. Keep the
[immediate rollback](rollback.md#immediate-rollback) accessible offline.
Redundant resolver design is deferred to
[multiple Pi-hole servers](advanced/multiple-pihole-servers.md).

## Material that must stay out of Git

Do not commit real Tailscale addresses, tailnet names, MagicDNS names, device
names, identities, email addresses, query logs, derived query-log data, private
domain lists, backups, captures, credentials, or tokens. The only permitted
literal Tailscale example address is the service resolver `100.100.100.100`.
Synthetic log-shaped fixtures must use `.txt`, not `.log`.
