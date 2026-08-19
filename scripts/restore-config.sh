#!/usr/bin/env bash
set -euo pipefail

# Exit contract:
# 0 dry-run completed, or restore applied and Pi-hole returned healthy
# 1 restore applied with a non-fatal warning
# 2 restore failed or was refused for a version mismatch
# 64 invalid arguments

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BACKUP_DIR=${XDG_STATE_HOME:-${HOME}/.local/state}/pihole-tailscale-backups
ARCHIVE=
API_URL=http://127.0.0.1
CA_CERT=
HTTP_TIMEOUT=15
APPLY=false
EXPLICIT_DRY_RUN=false
YES=false
FORCE_VERSION_MISMATCH=false
PASSWORD_STDIN=false

usage() {
  cat <<'EOF'
Usage: restore-config.sh [ARCHIVE] [options]

Validates a Pi-hole Teleporter ZIP and previews the import by default. --apply
uses the supported local Pi-hole v6 API and requires confirmation. The API
triggers the relevant Pi-hole restart. A setting-by-setting diff is not exposed
by Teleporter; the preview reports the exact archive submitted and its import
categories without exposing configuration contents.

Options:
  --backup-dir DIRECTORY       Directory used when ARCHIVE is omitted.
  --dry-run                    Validate and preview without writing. Default.
  --apply                      Import through the local Pi-hole API.
  --yes                        Skip the write confirmation.
  --force-version-mismatch     Permit a mismatched archive after explicit gating.
  --password-stdin             Read one API or application password line from stdin.
  --api-url URL                Loopback Pi-hole API base. Default: http://127.0.0.1.
  --cacert FILE                CA certificate for a loopback HTTPS API.
  --timeout SECONDS            Per-HTTP-operation timeout. Default: 15.
  -h, --help                   Show this help.

Exit codes:
  0  Dry-run completed, or restore applied and services returned healthy.
  1  Restore applied with a non-fatal warning.
  2  Restore failed or was refused for a version mismatch.
  64 Invalid arguments.
EOF
}

while (($#)); do
  case $1 in
    --backup-dir)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      BACKUP_DIR=$2
      shift 2
      ;;
    --dry-run)
      EXPLICIT_DRY_RUN=true
      shift
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    --yes)
      YES=true
      shift
      ;;
    --force-version-mismatch)
      FORCE_VERSION_MISMATCH=true
      shift
      ;;
    --password-stdin)
      PASSWORD_STDIN=true
      shift
      ;;
    --api-url)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      API_URL=${2%/}
      shift 2
      ;;
    --cacert)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      CA_CERT=$2
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      HTTP_TIMEOUT=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit "${EXIT_PASS}"
      ;;
    -*)
      usage >&2
      exit "${EXIT_USAGE}"
      ;;
    *)
      if [[ -n ${ARCHIVE} ]]; then
        fail "Only one archive can be supplied."
        exit "${EXIT_USAGE}"
      fi
      ARCHIVE=$1
      shift
      ;;
  esac
done

if [[ ${APPLY} == true && ${EXPLICIT_DRY_RUN} == true ]]; then
  fail "Choose either --dry-run or --apply."
  exit "${EXIT_USAGE}"
fi
if [[ ! ${HTTP_TIMEOUT} =~ ^[1-9][0-9]*$ ]]; then
  fail "Timeout must be a positive integer."
  exit "${EXIT_USAGE}"
fi
case ${API_URL} in
  http://127.0.0.1|https://127.0.0.1|http://localhost|https://localhost|http://\[::1\]|https://\[::1\]) ;;
  *)
    fail "The restore API URL must be a loopback HTTP or HTTPS address."
    exit "${EXIT_USAGE}"
    ;;
esac
if [[ -n ${CA_CERT} && ! -r ${CA_CERT} ]]; then
  fail "CA certificate is not readable: ${CA_CERT}"
  exit "${EXIT_USAGE}"
fi
if [[ ${PASSWORD_STDIN} == true && ${APPLY} != true ]]; then
  fail "--password-stdin is valid only with --apply."
  exit "${EXIT_USAGE}"
fi

for dependency in curl jq pihole pihole-FTL systemctl unzip; do
  require_command "${dependency}" || true
done
if ((FAIL_COUNT > 0)); then
  exit "${EXIT_FAIL}"
fi

if [[ -z ${ARCHIVE} ]]; then
  if [[ ! -d ${BACKUP_DIR} ]]; then
    fail "Backup directory does not exist: ${BACKUP_DIR}"
    exit "${EXIT_FAIL}"
  fi
  ARCHIVE=$(find "${BACKUP_DIR}" -maxdepth 1 -type f \
    -name 'pihole-teleporter-*.zip' -printf '%T@ %p\n' | \
    sort -rn | head -n 1 | cut -d' ' -f2-)
fi
if [[ -z ${ARCHIVE} || ! -f ${ARCHIVE} || ! -r ${ARCHIVE} ]]; then
  fail "No readable Teleporter archive was found."
  exit "${EXIT_FAIL}"
fi
if [[ ! -s ${ARCHIVE} ]]; then
  fail "Archive is empty: ${ARCHIVE}"
  exit "${EXIT_FAIL}"
fi
if ! unzip -tqq "${ARCHIVE}"; then
  fail "Archive failed ZIP integrity verification."
  exit "${EXIT_FAIL}"
fi

archive_entries=$(unzip -Z1 "${ARCHIVE}")
if grep -Eq '(^/|(^|/)\.\.(/|$)|\\)' <<<"${archive_entries}"; then
  fail "Archive contains an unsafe path."
  exit "${EXIT_FAIL}"
fi

ftl_version_output=$(pihole-FTL --version 2>/dev/null || true)
ftl_version=$(extract_version <<<"${ftl_version_output}" || true)
if [[ -z ${ftl_version} || ${ftl_version%%.*} != 6 ]]; then
  fail "This restore wrapper requires Pi-hole FTL v6."
  exit "${EXIT_FAIL}"
fi
if ! version_at_least "${ftl_version}" 6.7; then
  fail "Pi-hole FTL ${ftl_version} is below 6.7. Upgrade before importing an archive."
  exit "${EXIT_FAIL}"
fi

archive_major=5
if grep -Eq '(^|/)etc/pihole/pihole\.toml$' <<<"${archive_entries}"; then
  archive_major=6
fi
version_mismatch=false
if [[ ${archive_major} != "${ftl_version%%.*}" ]]; then
  version_mismatch=true
  if [[ ${FORCE_VERSION_MISMATCH} != true ]]; then
    fail "Archive appears to be Pi-hole v${archive_major}, but installed FTL is v${ftl_version%%.*}. Use --force-version-mismatch only after reviewing compatibility."
    exit "${EXIT_FAIL}"
  fi
  warn "Version mismatch override selected: archive v${archive_major}, installed FTL v${ftl_version%%.*}."
fi

emit_line "PREVIEW: Archive: ${ARCHIVE}"
emit_line "PREVIEW: Installed FTL: ${ftl_version}; detected archive major: ${archive_major}."
entry_count=$(wc -l <<<"${archive_entries}" | tr -d ' ')
emit_line "PREVIEW: ${entry_count} archive entries will be submitted to Pi-hole Teleporter."

declare -A category_patterns=(
  [configuration]='pihole.toml|setupVars.conf'
  [gravity-and-lists]='gravity.db|adlists|domainlist|whitelist|blacklist'
  [local-dns]='custom.list|dnsmasq|hosts|cname'
  [dhcp]='dhcp'
)
for category in configuration gravity-and-lists local-dns dhcp; do
  if grep -Eqi "${category_patterns[${category}]}" <<<"${archive_entries}"; then
    emit_line "PREVIEW: Import category present: ${category}"
  fi
done
emit_line "PREVIEW: Pi-hole decides which supported entries change or are ignored. Teleporter does not expose a setting-by-setting dry-run diff."

if [[ ${APPLY} != true ]]; then
  pass "Dry-run complete. No configuration was changed."
  exit "${EXIT_PASS}"
fi

if [[ ${YES} != true ]]; then
  confirmation_word=RESTORE
  if [[ ${version_mismatch} == true ]]; then
    confirmation_word=RESTORE-MISMATCH
  fi
  printf 'Type %s to import this archive: ' "${confirmation_word}" >&2
  read -r confirmation
  if [[ ${confirmation} != "${confirmation_word}" ]]; then
    fail "Restore cancelled."
    exit "${EXIT_FAIL}"
  fi
fi

api_password=
if [[ ${PASSWORD_STDIN} == true ]]; then
  IFS= read -r api_password
else
  printf 'Pi-hole API or application password: ' >&2
  IFS= read -r -s api_password
  printf '\n' >&2
fi
if [[ -z ${api_password} ]]; then
  fail "An API or application password is required for a privileged Teleporter import."
  exit "${EXIT_FAIL}"
fi

curl_tls=()
if [[ -n ${CA_CERT} ]]; then
  curl_tls=(--cacert "${CA_CERT}")
fi
auth_payload=$(printf '%s' "${api_password}" | jq -Rs '{password:.}')
unset api_password
auth_response=$(printf '%s' "${auth_payload}" | curl --silent --show-error \
  --max-time "${HTTP_TIMEOUT}" "${curl_tls[@]}" \
  --header 'Content-Type: application/json' --data-binary @- \
  --write-out $'\n%{http_code}' "${API_URL}/api/auth" 2>/dev/null || true)
unset auth_payload
auth_code=${auth_response##*$'\n'}
auth_body=${auth_response%$'\n'*}
if [[ ${auth_code} != 200 ]]; then
  unset auth_response auth_body
  fail "Pi-hole API authentication failed with HTTP ${auth_code:-unknown}."
  exit "${EXIT_FAIL}"
fi
sid=$(jq -r '.session.sid // empty' <<<"${auth_body}")
unset auth_response auth_body
if [[ -z ${sid} ]]; then
  fail "Pi-hole API authentication returned no session identifier."
  exit "${EXIT_FAIL}"
fi

# shellcheck disable=SC2317,SC2329
logout() {
  if [[ -n ${sid:-} ]]; then
    printf 'header = "X-FTL-SID: %s"\n' "${sid}" | curl --silent \
      --max-time "${HTTP_TIMEOUT}" "${curl_tls[@]}" --config - \
      --request DELETE "${API_URL}/api/auth" >/dev/null 2>&1 || true
  fi
}
trap logout EXIT

import_response=$(printf 'header = "X-FTL-SID: %s"\n' "${sid}" | curl \
  --silent --show-error --max-time "${HTTP_TIMEOUT}" "${curl_tls[@]}" \
  --config - --form "file=@${ARCHIVE};type=application/zip" \
  --write-out $'\n%{http_code}' "${API_URL}/api/teleporter" 2>/dev/null || true)
import_code=${import_response##*$'\n'}
unset import_response
if [[ ${import_code} != 200 ]]; then
  fail "Pi-hole Teleporter import failed with HTTP ${import_code:-unknown}."
  exit "${EXIT_FAIL}"
fi
pass "Pi-hole accepted the Teleporter import and initiated its supported restart."

service_ready=false
for _ in {1..15}; do
  if systemctl is-active --quiet pihole-FTL; then
    service_ready=true
    break
  fi
  sleep 1
done
if [[ ${service_ready} != true ]]; then
  fail "pihole-FTL did not return active after the import."
  exit "${EXIT_FAIL}"
fi

pihole_status=$(pihole status 2>/dev/null || true)
if [[ -z ${pihole_status} ]]; then
  warn "pihole-FTL is active, but the Pi-hole status command did not respond."
else
  pass "Pi-hole service restarted and the status command responded."
fi

if ((WARN_COUNT > 0)); then
  exit "${EXIT_WARN}"
fi
exit "${EXIT_PASS}"
