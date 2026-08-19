# iOS configuration

The current Tailscale App Store listing requires iOS 15 or newer. Verify the
requirement again before deployment because App Store compatibility can change.

## Connect the iPhone

1. Install Tailscale from the official App Store listing.
2. Open the app and approve the iOS VPN configuration prompt.
3. Join the correct tailnet using the intended identity.
4. Complete device approval if the tailnet requires it.
5. Connect Tailscale.
6. Confirm **Use Tailscale DNS settings** is enabled or enforced by approved
   device policy.
7. Record the Tailscale address locally for query-log correlation. Do not commit
   it.

## Required tests

Perform each test separately and record the date, iOS version, Tailscale version,
network path, and sanitized result.

1. Test on Wi-Fi.
2. Disable Wi-Fi and test on cellular.
3. Reboot the phone, reconnect if necessary, and test again.
4. Background and resume Tailscale, then test again.
5. Confirm a fresh allowed-domain and blocked-domain query appears under the
   expected client in Pi-hole.
6. Confirm no Exit Node is selected for the DNS-only design.

Use [Testing](testing.md) for the exact layers. Safari alone is not sufficient
because iCloud Private Relay can use encrypted DNS for Safari traffic.

## VPN On Demand

VPN On Demand is optional. In the Tailscale app, open the profile menu, select
**VPN On Demand**, and choose rules for Wi-Fi and cellular. Test every selected
rule. Incorrect `Never` or network-list rules can immediately disconnect the
tunnel.

Only one VPN app can be active on iOS. Connecting another VPN displaces
Tailscale. If another VPN is connected while Tailscale On Demand is enabled,
iOS disables Tailscale On Demand until Tailscale is manually reconnected.

Managed deployments should use current Tailscale system-policy guidance. Do not
claim always-on behavior unless the supervised-device configuration enforces it
and it has been tested.

## Conflicts and limitations

- iCloud Private Relay protects Safari traffic with its own relay and encrypted
  DNS behavior. Do not disable it globally by default. Test the affected path
  and use the narrowest acceptable change, such as the network-specific
  **Limit IP Address Tracking** control, only after explaining the privacy loss.
- A custom DNS profile, content filter, or MDM-managed VPN can take precedence.
- Applications can use their own DNS-over-HTTPS, DNS-over-TLS, proxy, or relay.
- Captive portals can require temporary tunnel disconnection before sign-in.
- Low Power Mode, backgrounding, carrier transitions, reboot, and iOS updates can
  affect persistence. Test observed behavior instead of promising it.

## Emergency recovery

Disconnect Tailscale or disable its DNS acceptance to return the phone to its
normal network resolver. If the problem affects the whole tailnet, an authorized
administrator can disable **Override DNS servers** in the Admin Console.
