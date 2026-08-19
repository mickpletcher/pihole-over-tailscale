# Exit Node

An Exit Node is not required for Pi-hole DNS filtering.

```text
DNS-only:
DNS -> Pi-hole through Tailscale
Internet traffic -> cellular or Wi-Fi directly
```

```text
Exit Node:
DNS -> selected resolver behavior
All Internet traffic -> home network through Tailscale
```

Use an Exit Node when full-tunnel privacy on public Wi-Fi, a home public IP, or
access to home-only resources is required. It adds latency, consumes home upload
bandwidth, and makes the client's Internet path dependent on the home uplink.
The apparent public IP becomes the Exit Node's egress address and can change
when that connection changes.

Tailscale's current DNS controls include **Use with exit node** for custom
nameservers. Enable it only when Pi-hole should remain the resolver while a
client uses an Exit Node. Otherwise the Exit Node's resolver behavior can take
precedence. Reverify this option against [references](../references.md) before a
deployment because client behavior is version-sensitive.

An Exit Node increases the compromised-host blast radius because it can carry
all client Internet traffic, not only DNS. Roll back by deselecting the Exit
Node first, then verify the DNS-only path.
