#!/usr/bin/env bash
set -euo pipefail

# Shared exit contract:
# 0 PASS or successful operation
# 1 WARN or partial result
# 2 FAIL
# 64 invalid usage

readonly EXIT_PASS=0
readonly EXIT_WARN=1
readonly EXIT_FAIL=2
readonly EXIT_USAGE=64

QUIET=${QUIET:-false}
REDACT_OUTPUT=${REDACT_OUTPUT:-false}
WARN_COUNT=0
FAIL_COUNT=0

redact_sensitive() {
  sed -E \
    -e 's/100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}/[redacted-tailscale-ip]/g' \
    -e 's/([[:alnum:]_-]+\.)+[[:alnum:]_-]+\.ts\.net/[redacted-tailnet-name]/g'
}

emit_line() {
  local line=$1
  if [[ ${REDACT_OUTPUT} == true ]]; then
    printf '%s\n' "${line}" | redact_sensitive
  else
    printf '%s\n' "${line}"
  fi
}

pass() {
  if [[ ${QUIET} != true ]]; then
    emit_line "PASS: $*"
  fi
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  emit_line "WARN: $*" >&2
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  emit_line "FAIL: $*" >&2
}

die_usage() {
  emit_line "FAIL: $*" >&2
  return "${EXIT_USAGE}"
}

require_command() {
  local command_name=$1
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "Required command not found: ${command_name}"
    return "${EXIT_FAIL}"
  fi
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    fail "This operation requires root privileges. Run it with sudo."
    return "${EXIT_FAIL}"
  fi
}

run_with_timeout() {
  local seconds=$1
  shift
  timeout --signal=TERM "${seconds}s" "$@"
}

version_at_least() {
  local installed=$1
  local required=$2
  [[ $(printf '%s\n%s\n' "${required}" "${installed}" | sort -V | head -n 1) == "${required}" ]]
}

extract_version() {
  grep -Eo '[0-9]+(\.[0-9]+){1,3}' | head -n 1
}

status_exit() {
  if ((FAIL_COUNT > 0)); then
    return "${EXIT_FAIL}"
  fi
  if ((WARN_COUNT > 0)); then
    return "${EXIT_WARN}"
  fi
  return "${EXIT_PASS}"
}

write_redacted_file() {
  local destination=$1
  redact_sensitive >"${destination}"
}

is_valid_tailscale_ipv4() {
  local address=$1
  local first second third fourth
  IFS=. read -r first second third fourth <<<"${address}"
  [[ ${first:-} == 100 ]] || return 1
  [[ ${second:-} =~ ^[0-9]+$ && ${second} -ge 64 && ${second} -le 127 ]] || return 1
  [[ ${third:-} =~ ^[0-9]+$ && ${third} -le 255 ]] || return 1
  [[ ${fourth:-} =~ ^[0-9]+$ && ${fourth} -le 255 ]] || return 1
}
