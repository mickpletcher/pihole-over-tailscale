# Subnet Routing

Subnet routing is not required when Pi-hole is reached through its own Tailscale
address. Keep it out of the core deployment.

Use a subnet router only when a remote device must reach other home systems by
LAN address or when Tailscale-capable infrastructure must proxy access for
devices that cannot run Tailscale themselves. Advertising a LAN subnet does not
automatically make Pi-hole accept the resulting DNS source. Recheck Pi-hole's
listening mode, source addresses, host firewall, and Tailscale policy.

Avoid advertising a prefix that overlaps a network the client is currently on.
Overlapping routes can make local resources unreachable or send traffic through
the wrong site. Subnet approval, route acceptance, access policy, IP forwarding,
and firewall changes are separate live changes and require their own validation
and rollback.
