# Multiple Pi-hole Servers

A future redundant design can assign two equivalently filtered Pi-hole servers
as Tailscale nameservers.

Both servers must provide equivalent blocklists, allowlists, local DNS records,
upstreams, and blocking behavior. Resolver lists are not guaranteed ordered
primary/secondary failover. Clients or Tailscale can query more than one server,
including in parallel, so drift produces inconsistent answers rather than clean
failover.

Synchronize only an explicit configuration set. Protect administrator secrets,
API credentials, query data, and host-specific settings. Use backups and staged
validation so synchronization cannot destructively overwrite a healthy peer.

Run Layer 1 independently on both servers. From a remote authorized client,
test UDP and TCP 53 against each Tailscale address. Then configure both addresses
as custom Tailscale nameservers and repeat client system-resolver and iPhone
tests. Failure testing must prove what clients actually do when either server is
unavailable.

The work remains deferred. See [high availability](high-availability.md) and
[`FUTURE-UPGRADES.md`](../../FUTURE-UPGRADES.md).
