#!/usr/bin/env bash
set -euo pipefail

# Exit contract:
# 0 all requested direct DNS checks passed
# 1 permitted domain resolved but the optional blocked check was inconclusive
# 2 direct reachability or resolution failed
# 64 invalid arguments or invalid server address

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SERVER=
ALLOWED_DOMAIN=example.com
BLOCKED_DOMAIN=
DNS_TIMEOUT=5

usage() {
  cat <<'EOF'
Usage: verify-dns.sh PIHOLE_TAILSCALE_IP [options]

Runs read-only, direct-server DNS checks over UDP and TCP. This does not prove
that the client's system resolver automatically uses Tailscale DNS.

Options:
  --allowed-domain DOMAIN  Permitted domain expected to resolve. Default: example.com.
  --blocked-domain DOMAIN  Optional known domain expected to be blocked.
  --timeout SECONDS        Per-query timeout. Default: 5.
  -h, --help               Show this help.

Exit codes:
  0  All requested checks passed.
  1  Permitted domain resolved, but blocked-domain result was inconclusive.
  2  Reachability or resolution failed.
  64 Invalid arguments or invalid server address.
EOF
}

if (($# == 0)); then
  usage >&2
  exit "${EXIT_USAGE}"
fi

case ${1:-} in
  -h|--help)
    usage
    exit "${EXIT_PASS}"
    ;;
  -*)
    usage >&2
    exit "${EXIT_USAGE}"
    ;;
  *)
    SERVER=$1
    shift
    ;;
esac

while (($#)); do
  case $1 in
    --allowed-domain)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      ALLOWED_DOMAIN=$2
      shift 2
      ;;
    --blocked-domain)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      BLOCKED_DOMAIN=$2
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      DNS_TIMEOUT=$2
      shift 2
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

if ! is_valid_tailscale_ipv4 "${SERVER}"; then
  fail "Server must be a valid IPv4 address in the Tailscale CGNAT range."
  exit "${EXIT_USAGE}"
fi
if [[ -z ${ALLOWED_DOMAIN} || ${ALLOWED_DOMAIN} == -* || ${ALLOWED_DOMAIN} =~ [[:space:]] ]]; then
  fail "Allowed domain is invalid."
  exit "${EXIT_USAGE}"
fi
if [[ -n ${BLOCKED_DOMAIN} && (${BLOCKED_DOMAIN} == -* || ${BLOCKED_DOMAIN} =~ [[:space:]]) ]]; then
  fail "Blocked domain is invalid."
  exit "${EXIT_USAGE}"
fi
if [[ ! ${DNS_TIMEOUT} =~ ^[1-9][0-9]*$ ]]; then
  fail "Timeout must be a positive integer."
  exit "${EXIT_USAGE}"
fi

require_command dig || exit "${EXIT_FAIL}"
require_command timeout || exit "${EXIT_FAIL}"

query_dns() {
  local transport=$1
  local domain=$2
  local tcp_flag=()
  if [[ ${transport} == TCP ]]; then
    tcp_flag=(+tcp)
  fi
  run_with_timeout "$((DNS_TIMEOUT + 1))" dig "${tcp_flag[@]}" \
    +time="${DNS_TIMEOUT}" +tries=1 +noall +comments +answer \
    "@${SERVER}" "${domain}" A
}

check_allowed() {
  local transport=$1
  local output
  if ! output=$(query_dns "${transport}" "${ALLOWED_DOMAIN}" 2>&1); then
    fail "${transport} DNS query to ${SERVER} failed for ${ALLOWED_DOMAIN}."
    return 1
  fi
  if ! grep -q 'status: NOERROR' <<<"${output}" || ! grep -Eq '[[:space:]]A[[:space:]]+[0-9.]+' <<<"${output}"; then
    fail "${transport} reached DNS but ${ALLOWED_DOMAIN} did not return an IPv4 answer."
    return 1
  fi
  pass "${transport} direct-server DNS resolved ${ALLOWED_DOMAIN}."
}

allowed_failed=false
check_allowed UDP || allowed_failed=true
check_allowed TCP || allowed_failed=true
if [[ ${allowed_failed} == true ]]; then
  emit_line "DIAGNOSTIC: The most probable cause is Pi-hole's interface listening mode rejecting traffic from tailscale0."
  emit_line "DIAGNOSTIC: See docs/pihole-configuration.md#critical-interface-listening-behavior and verify both firewall protocols."
  exit "${EXIT_FAIL}"
fi

if [[ -n ${BLOCKED_DOMAIN} ]]; then
  blocked_output=
  if ! blocked_output=$(query_dns UDP "${BLOCKED_DOMAIN}" 2>&1); then
    warn "The allowed domain resolved, but the blocked-domain query failed."
    exit "${EXIT_WARN}"
  fi
  if grep -q 'status: NXDOMAIN' <<<"${blocked_output}"; then
    pass "Blocked domain returned NXDOMAIN."
  elif grep -Eq '[[:space:]]A[[:space:]]+0\.0\.0\.0([[:space:]]|$)' <<<"${blocked_output}"; then
    pass "Blocked domain returned a zero-address blocking response."
  elif grep -q 'status: NOERROR' <<<"${blocked_output}" && \
    ! grep -Eq '[[:space:]]A[[:space:]]+[0-9.]+' <<<"${blocked_output}"; then
    pass "Blocked domain returned NODATA."
  else
    warn "The blocked-domain response was not a recognized Pi-hole blocking response. Confirm the active denylist and query log."
    exit "${EXIT_WARN}"
  fi
fi

pass "Direct-server UDP and TCP checks completed. Test the client system resolver separately."
