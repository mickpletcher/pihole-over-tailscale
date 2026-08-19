# Maintenance

This guide covers ongoing operation after the deployment has passed the
applicable [test layers](testing.md).

## Install the scheduled health check

Installing or enabling a unit changes the host. Review the files and obtain the
required authorization first. The service intentionally runs as `root` because
it inspects service and socket state. The unit hardening limits its filesystem
and privilege surface, but root execution still increases impact if the script
is modified.

Copy the script and its shared library out of the Git checkout:

```bash
sudo install -d -o root -g root -m 0755 /usr/local/lib/pihole-tailscale/lib
sudo install -o root -g root -m 0755 scripts/health-check.sh \
  /usr/local/lib/pihole-tailscale/health-check.sh
sudo install -o root -g root -m 0644 scripts/lib/common.sh \
  /usr/local/lib/pihole-tailscale/lib/common.sh
sudo install -o root -g root -m 0644 \
  systemd/pihole-tailscale-healthcheck.service /etc/systemd/system/
sudo install -o root -g root -m 0644 \
  systemd/pihole-tailscale-healthcheck.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pihole-tailscale-healthcheck.timer
```

The timer runs hourly with up to 600 seconds of random delay. Configure the
server address by editing the service unit's `ExecStart` placeholder before
enablement.

Verify scheduling and one completed run:

```bash
systemctl list-timers pihole-tailscale-healthcheck.timer
sudo systemctl start pihole-tailscale-healthcheck.service
systemctl show pihole-tailscale-healthcheck.service -p Result -p ExecMainStatus
journalctl -u pihole-tailscale-healthcheck.service
```

The script exits `1` for warnings. `SuccessExitStatus=1` keeps that state from
being reported by systemd as a failed unit. WARN and FAIL details still appear
in the journal. An exit of `2` is a unit failure.

### Remove the timer

```bash
sudo systemctl disable --now pihole-tailscale-healthcheck.timer
sudo rm /etc/systemd/system/pihole-tailscale-healthcheck.timer
sudo rm /etc/systemd/system/pihole-tailscale-healthcheck.service
sudo systemctl daemon-reload
sudo rm -r /usr/local/lib/pihole-tailscale
```

Review each absolute path before running these destructive commands.

### Cron alternative

Use cron only on a non-systemd host. Copy the script and `lib/` directory to the
same installed path, then add this root crontab entry with the real address:

```cron
17 * * * * /usr/local/lib/pihole-tailscale/health-check.sh --quiet --server <PIHOLE_TAILSCALE_IP>
```

Cron has no randomized delay or unit hardening. Route its output to the host's
protected logging system.

## Interpret results

Layer 1 checks are defined in the script. `PASS` means the individual local
check succeeded. `WARN` covers conditions such as key expiry within 14 days,
less than 10 percent disk free, or gravity older than 30 days. `FAIL` covers an
unhealthy service, backend, listener, DNS path, blocking state, or unsupported
Pi-hole baseline. Use [troubleshooting](troubleshooting.md) before changing
state.

## Backups

Create a verified backup before Pi-hole changes and at least monthly:

```bash
sudo ./scripts/backup-config.sh
sudo ./scripts/restore-config.sh --dry-run
```

The second command previews the newest archive. Store archives outside Git,
transfer them through an encrypted channel, and prune only after reviewing the
proposed set:

```bash
sudo ./scripts/backup-config.sh --dry-run --prune --retention 7
sudo ./scripts/backup-config.sh --prune --retention 7
```

## Updates and reviews

### Pi-hole

Back up first. Read the Pi-hole release notes, apply the supported update, then
verify FTL version, listening mode, blocking status, and Layers 1 through 5.

### Tailscale

Read the Tailscale release notes, update through the installed package source,
then verify daemon state, authentication, node key expiry, Layers 1 through 3,
and both iPhone paths.

### Tailnet

Monthly, review devices, remove stale entries, review pending key expirations,
and inspect all grants and legacy ACLs for broad additive access. Re-run Layer 6
after policy changes with explicit authorization.

### Blocklists, disk, and logs

Update gravity on the chosen cadence and confirm the designated blocked and
allowed domains still behave as expected. Review disk use and journal/Pi-hole
retention monthly. Do not solve capacity problems by exporting sensitive query
logs into the repository.

### Documentation baseline

Quarterly and before a major update, revisit [references](references.md). Check
the current first-party Pi-hole, Tailscale, Apple, and Linux documentation.
Update the verification date only after fetching the page and reconciling the
instructions. Re-run the test layers affected by any changed claim.

## Recurring checklist

| Interval | Task | Reverification |
| --- | --- | --- |
| Hourly | Automated health check | Layer 1 |
| Weekly | Review WARN/FAIL journal entries | Layer 1 and targeted diagnostics |
| Monthly | Create and dry-run a backup; review disk, logs, lists, devices, and keys | Layers 1 to 3 |
| Quarterly | Review tailnet policy and documentation references | Layers 1 to 6 as applicable |
| Before and after updates | Backup, update one component, verify | Layers affected by that component |
| Annually | Approved outage and rollback exercise | Layer 7 |
