# Rollback

Run one stage at a time. Verify ordinary DNS from a LAN client and a tailnet
client after every stage. Stop when service is restored. Reinstalling Pi-hole is
not part of this rollback.

## Immediate rollback

If DNS failure prevents access to the Tailscale Admin Console, use one affected
client first. Turn off **Use Tailscale DNS settings** on that client. If the
control is unavailable, disconnect Tailscale temporarily. The client should
return to its Wi-Fi or carrier resolver, restoring access while bypassing
Pi-hole filtering.

## Staged rollback

1. **Disable Tailscale DNS on one affected client.** Reversible: yes. Expected
   end state: that client resolves through its local or carrier DNS and no
   longer receives Pi-hole filtering.
2. **Disable Override local DNS in the Tailscale Admin Console.** Reversible:
   yes. Expected end state: connected devices can use local resolvers again.
3. **Remove the Pi-hole custom global nameserver if required.** Reversible: yes.
   Expected end state: the broken resolver is no longer distributed.
4. **Restore the previous Tailscale DNS settings from the local evidence
   capture.** Reversible: yes if the current settings are captured first.
   Expected end state: the tailnet uses its last known-good resolver policy.
5. **Disconnect Tailscale on the phone if necessary.** Reversible: yes. Expected
   end state: iOS uses Wi-Fi or carrier DNS and Pi-hole filtering is bypassed.
6. **Restore the previous Pi-hole listening mode from `evidence/`.** Reversible:
   yes if both states are recorded. Expected end state: Pi-hole listens on the
   interfaces used before this project.
7. **Restore the prior host firewall rules from `evidence/`.** Reversible: yes
   if both rulesets are available. Expected end state: the host returns to its
   pre-deployment firewall posture. Never open public DNS as a recovery step.

8. **Restore Pi-hole configuration with the wrapper.** Reversible: only when a
   current backup exists. Expected end state: Pi-hole contains the backed-up
   v6 configuration:

   ```bash
   sudo ./scripts/restore-config.sh --dry-run /secure/path/pihole-backup.zip
   sudo ./scripts/restore-config.sh --apply /secure/path/pihole-backup.zip
   ```

   The preview validates the archive and reports imported categories. Pi-hole's
   supported Teleporter interface does not provide a setting-by-setting diff.
   Review the archive and preview before approving the write.

9. **Remove the health check timer and service.** Reversible: yes. Expected end
   state: no scheduled repository script remains. Use the removal procedure in
   [maintenance](maintenance.md#remove-the-timer).

10. **Optionally remove Tailscale from the Pi-hole host.** Reversible only by
    reinstalling and reenrolling Tailscale. Expected end state: the host has no
    Tailscale interface. Do this only after DNS is stable through the restored
    path and after preserving any evidence needed for incident review.
11. **Verify after every stage.** From a LAN client and an authorized tailnet
    client, test a fresh allowed domain. Where Pi-hole is still intended to
    serve the client, also test `<KNOWN_BLOCKED_DOMAIN>` and correlate the query
    timestamp.

## Restore a Teleporter backup

Use stage 8 of [staged rollback](#staged-rollback). It is the only supported
configuration restore path in this repository.

## Remove Tailscale

Use stage 10 of [staged rollback](#staged-rollback). Treat removal as optional
final cleanup, not as the first DNS recovery action.

Live policy, firewall, service, and client changes require explicit approval.
