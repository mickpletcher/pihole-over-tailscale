# High Availability

High availability is deferred. With one Pi-hole configured as the global
Tailscale nameserver, that server is a single point of DNS failure while clients
remain connected and accept the override. The tracked work is in
[`FUTURE-UPGRADES.md`](../../FUTURE-UPGRADES.md).

Possible approaches include a second nameserver entry, keepalived for a LAN
virtual IP, or containerized failover. A LAN virtual IP does not float a
Tailscale node identity or its Tailscale address. None of these options is safe
to prescribe without selecting ownership, synchronization, detection, and
client behavior.

Controlled live failover testing is required. Geographic and power diversity
can matter more than process monitoring on two instances at the same site. See
[multiple Pi-hole servers](multiple-pihole-servers.md) for the target resolver
design. Do not add this complexity to the initial deployment.
