#!/usr/bin/env bash
set -euo pipefail

# Exit contract:
# 0 every Layer 1 check passed
# 1 one or more warnings and no failures
# 2 one or more failures
# 64 invalid arguments

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SERVER=
ALLOWED_DOMAIN=example.com
DNS_TIMEOUT=5
KEY_EXPIRY_DAYS=14
DISK_FREE_PERCENT=10
GRAVITY_MAX_DAYS=30
GRAVITY_DATABASE=/etc/pihole/gravity.db

usage() {
  cat <<'EOF'
Usage: health-check.sh [options]

Runs the complete read-only Validation Layer 1 check set on the Pi-hole host.
It does not prove that a remote client can reach or automatically use Pi-hole.

Options:
  --server ADDRESS          Pi-hole Tailscale IPv4 address. Auto-detected if omitted.
  --allowed-domain DOMAIN  Permitted domain expected to resolve. Default: example.com.
  --timeout SECONDS        Per-query timeout. Default: 5.
  --key-expiry-days DAYS   Warning threshold. Default: 14.
  --disk-free-percent N    Warning threshold. Default: 10.
  --gravity-max-days DAYS  Warning threshold. Default: 30.
  --gravity-database FILE  Alternate gravity database path for validation or testing.
  --quiet                  Print WARN and FAIL only and redact private tailnet values.
  -h, --help               Show this help.

Layer 1 checks:
  tailscaled service; backend, authentication, and key expiry; pihole-FTL
  service and version; UDP and TCP 53 listeners; tailscale0 address and binding;
  direct DNS; permitted-domain and host upstream resolution; disk space; Pi-hole
  status, blocking state, gravity database existence, and gravity age.

Exit codes:
  0  All checks PASS.
  1  One or more WARN and no FAIL.
  2  One or more FAIL.
  64 Invalid arguments.
EOF
}

while (($#)); do
  case $1 in
    --server)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      SERVER=$2
      shift 2
      ;;
    --allowed-domain)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      ALLOWED_DOMAIN=$2
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      DNS_TIMEOUT=$2
      shift 2
      ;;
    --key-expiry-days)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      KEY_EXPIRY_DAYS=$2
      shift 2
      ;;
    --disk-free-percent)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      DISK_FREE_PERCENT=$2
      shift 2
      ;;
    --gravity-max-days)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      GRAVITY_MAX_DAYS=$2
      shift 2
      ;;
    --gravity-database)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      GRAVITY_DATABASE=$2
      shift 2
      ;;
    --quiet)
      QUIET=true
      REDACT_OUTPUT=true
      shift
      ;;
    -h|--help)
      usage
      exit "${EXIT_PASS}"
      ;;
    *)
      usage >&2
      exit "${EXIT_USAGE}"
      ;;
  esac
done

for numeric_value in "${DNS_TIMEOUT}" "${KEY_EXPIRY_DAYS}" "${DISK_FREE_PERCENT}" "${GRAVITY_MAX_DAYS}"; do
  if [[ ! ${numeric_value} =~ ^[0-9]+$ ]]; then
    fail "Thresholds and timeouts must be non-negative integers."
    exit "${EXIT_USAGE}"
  fi
done
if ((DNS_TIMEOUT < 1 || DISK_FREE_PERCENT > 100)); then
  fail "Timeout must be positive and disk threshold cannot exceed 100."
  exit "${EXIT_USAGE}"
fi
if [[ -z ${ALLOWED_DOMAIN} || ${ALLOWED_DOMAIN} == -* || ${ALLOWED_DOMAIN} =~ [[:space:]] ]]; then
  fail "Allowed domain is invalid."
  exit "${EXIT_USAGE}"
fi
if [[ -n ${SERVER} ]] && ! is_valid_tailscale_ipv4 "${SERVER}"; then
  fail "Server must be a valid IPv4 address in the Tailscale CGNAT range."
  exit "${EXIT_USAGE}"
fi

for dependency in date df dig ip jq pihole pihole-FTL ss stat systemctl tailscale timeout; do
  require_command "${dependency}" || true
done
if ((FAIL_COUNT > 0)); then
  exit "${EXIT_FAIL}"
fi

if systemctl is-active --quiet tailscaled; then
  pass "tailscaled service is active."
else
  fail "tailscaled service is not active."
fi

tailscale_json=
if tailscale_json=$(run_with_timeout 5 tailscale status --json 2>/dev/null); then
  backend_state=$(jq -r '.BackendState // "unknown"' <<<"${tailscale_json}")
  if [[ ${backend_state} == Running ]]; then
    pass "Tailscale backend is Running."
  else
    fail "Tailscale backend state is ${backend_state}."
  fi

  self_online=$(jq -r '.Self.Online // false' <<<"${tailscale_json}")
  if [[ ${self_online} == true ]]; then
    pass "Tailscale reports the local node online and authenticated."
  else
    fail "Tailscale does not report the local node online."
  fi

  key_expiry=$(jq -r '.Self.KeyExpiry // empty' <<<"${tailscale_json}")
  if [[ -n ${key_expiry} ]]; then
    if expiry_epoch=$(date -d "${key_expiry}" +%s 2>/dev/null); then
      now_epoch=$(date +%s)
      days_remaining=$(((expiry_epoch - now_epoch) / 86400))
      if ((days_remaining < 0)); then
        fail "Tailscale node key is expired."
      elif ((days_remaining <= KEY_EXPIRY_DAYS)); then
        warn "Tailscale node key expires in ${days_remaining} days."
      else
        pass "Tailscale node key expiry is outside the warning window."
      fi
    else
      warn "Tailscale key expiry was present but could not be parsed."
    fi
  else
    warn "Tailscale did not report a node key expiry value. Review the device record."
  fi
else
  fail "Could not read machine-readable Tailscale status."
fi

if [[ -z ${SERVER} ]]; then
  if SERVER=$(run_with_timeout 5 tailscale ip -4 2>/dev/null | head -n 1) && \
    is_valid_tailscale_ipv4 "${SERVER}"; then
    pass "Detected the Pi-hole Tailscale address."
  else
    fail "Could not detect a valid Tailscale IPv4 address. Pass --server explicitly."
    SERVER=
  fi
fi

if systemctl is-active --quiet pihole-FTL; then
  pass "pihole-FTL service is active."
else
  fail "pihole-FTL service is not active."
fi

ftl_version_output=$(pihole-FTL --version 2>/dev/null || true)
ftl_version=$(extract_version <<<"${ftl_version_output}" || true)
if [[ -z ${ftl_version} ]]; then
  fail "Could not determine the Pi-hole FTL version."
elif version_at_least "${ftl_version}" 6.7; then
  pass "Pi-hole FTL ${ftl_version} meets the 6.7 minimum."
else
  fail "Pi-hole FTL ${ftl_version} is below the required 6.7 restore-safe baseline."
fi

udp_listeners=$(ss -H -lun 'sport = :53' 2>/dev/null || true)
tcp_listeners=$(ss -H -ltn 'sport = :53' 2>/dev/null || true)
if [[ -n ${udp_listeners} ]]; then
  pass "UDP 53 has a listening socket."
else
  fail "UDP 53 has no listening socket."
fi
if [[ -n ${tcp_listeners} ]]; then
  pass "TCP 53 has a listening socket."
else
  fail "TCP 53 has no listening socket."
fi

tailscale_interface=$(ip -o -4 addr show dev tailscale0 2>/dev/null || true)
if [[ -n ${tailscale_interface} ]]; then
  pass "tailscale0 has an IPv4 address."
else
  fail "tailscale0 has no IPv4 address."
fi

if [[ -n ${SERVER} ]]; then
  listener_pattern="(${SERVER//./\\.}|0\\.0\\.0\\.0|\\*):53"
  if grep -Eq "${listener_pattern}" <<<"${udp_listeners}" && \
    grep -Eq "${listener_pattern}" <<<"${tcp_listeners}"; then
    pass "Both DNS protocols are bound to the Tailscale address or a wildcard listener."
  else
    fail "DNS is not bound for both protocols on the Tailscale path. Review Pi-hole listening mode."
  fi

  dns_output=$(run_with_timeout "$((DNS_TIMEOUT + 1))" dig +time="${DNS_TIMEOUT}" \
    +tries=1 +noall +comments +answer "@${SERVER}" "${ALLOWED_DOMAIN}" A 2>/dev/null || true)
  if grep -q 'status: NOERROR' <<<"${dns_output}" && \
    grep -Eq '[[:space:]]A[[:space:]]+[0-9.]+' <<<"${dns_output}"; then
    pass "DNS through the server Tailscale address resolved the permitted domain."
  else
    fail "DNS through the server Tailscale address failed for the permitted domain."
  fi
fi

host_dns=$(run_with_timeout "$((DNS_TIMEOUT + 1))" dig +time="${DNS_TIMEOUT}" \
  +tries=1 +short "${ALLOWED_DOMAIN}" A 2>/dev/null || true)
if grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<<"${host_dns}"; then
  pass "The host resolver completed upstream resolution."
else
  fail "The host resolver could not complete upstream resolution."
fi

available_percent=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print 100-$5}')
if [[ ${available_percent} =~ ^[0-9]+$ ]]; then
  if ((available_percent < DISK_FREE_PERCENT)); then
    warn "Root filesystem has ${available_percent}% free, below the ${DISK_FREE_PERCENT}% threshold."
  else
    pass "Root filesystem free space is above the warning threshold."
  fi
else
  fail "Could not determine root filesystem free space."
fi

pihole_status=$(pihole status 2>/dev/null || true)
if [[ -n ${pihole_status} ]]; then
  pass "Pi-hole status command responded."
else
  fail "Pi-hole status command did not respond."
fi
if grep -Eqi 'blocking[^[:alpha:]]+(is[[:space:]]+)?enabled|blocking:[[:space:]]+enabled' <<<"${pihole_status}"; then
  pass "Pi-hole blocking is enabled."
else
  fail "Pi-hole blocking is not reported as enabled."
fi

if [[ -f ${GRAVITY_DATABASE} ]]; then
  pass "Gravity database exists."
  gravity_epoch=$(stat -c %Y "${GRAVITY_DATABASE}")
  now_epoch=$(date +%s)
  gravity_age_days=$(((now_epoch - gravity_epoch) / 86400))
  if ((gravity_age_days > GRAVITY_MAX_DAYS)); then
    warn "Gravity database is ${gravity_age_days} days old."
  else
    pass "Gravity database age is within the ${GRAVITY_MAX_DAYS}-day threshold."
  fi
else
  fail "Gravity database does not exist at ${GRAVITY_DATABASE}."
fi

if ((FAIL_COUNT > 0)); then
  exit "${EXIT_FAIL}"
fi
if ((WARN_COUNT > 0)); then
  exit "${EXIT_WARN}"
fi
exit "${EXIT_PASS}"
