#!/usr/bin/env bash
set -euo pipefail

# Exit contract:
# 0 all safe repository tests passed
# 1 one or more tests failed
# 2 test harness could not run
# 64 invalid arguments

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
TESTS_RUN=0
TESTS_FAILED=0

# shellcheck disable=SC2317,SC2329
cleanup() {
  case ${TEST_TMP} in
    /tmp/*|/var/tmp/*) rm -r -- "${TEST_TMP}" ;;
  esac
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: run-tests.sh [--help]

Runs safe static, mocked, and local integration tests. It does not contact a
tailnet, change host services, install software, or use live Pi-hole data.

Exit codes:
  0  All tests passed.
  1  One or more tests failed.
  2  Test harness dependency or setup failure.
  64 Invalid arguments.
EOF
}

case ${1:-} in
  '') ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

pass_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf 'PASS: %s\n' "$1"
}

fail_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

assert_eq() {
  local expected=$1
  local actual=$2
  local name=$3
  if [[ ${actual} == "${expected}" ]]; then
    pass_test "${name}"
  else
    fail_test "${name}: expected ${expected}, got ${actual}"
    if [[ -n ${COMMAND_OUTPUT:-} ]]; then
      printf '  Command output: %s\n' "${COMMAND_OUTPUT}" >&2
    fi
  fi
}

assert_contains() {
  local text=$1
  local expected=$2
  local name=$3
  if grep -Fq -- "${expected}" <<<"${text}"; then
    pass_test "${name}"
  else
    fail_test "${name}: missing '${expected}'"
  fi
}

run_status() {
  set +e
  COMMAND_OUTPUT=$("$@" 2>&1)
  COMMAND_STATUS=$?
  set -e
}

for dependency in bash git jq python3 rg unzip; do
  if ! command -v "${dependency}" >/dev/null 2>&1; then
    printf 'FAIL: Test dependency not found: %s\n' "${dependency}" >&2
    exit 2
  fi
done

scripts=(
  scripts/install-tailscale.sh
  scripts/verify-dns.sh
  scripts/health-check.sh
  scripts/backup-config.sh
  scripts/restore-config.sh
)

for script in "${scripts[@]}"; do
  run_status bash "${ROOT}/${script}" --help
  assert_eq 0 "${COMMAND_STATUS}" "${script} --help exits 0"
  assert_contains "${COMMAND_OUTPUT}" 'Exit codes:' "${script} states its exit contract"
  for code in 0 1 2 64; do
    assert_contains "${COMMAND_OUTPUT}" "${code} " "${script} help includes exit ${code}"
  done

  run_status bash "${ROOT}/${script}" --definitely-invalid
  assert_eq 64 "${COMMAND_STATUS}" "${script} rejects invalid arguments"
done

run_status bash "${ROOT}/scripts/verify-dns.sh" --apply
assert_eq 64 "${COMMAND_STATUS}" 'verify-dns.sh rejects --apply'
run_status bash "${ROOT}/scripts/health-check.sh" --apply
assert_eq 64 "${COMMAND_STATUS}" 'health-check.sh rejects --apply'

printf 'ID=fedora\nID_LIKE=rhel\n' >"${TEST_TMP}/unsupported-os-release"
run_status bash "${ROOT}/scripts/install-tailscale.sh" \
  --os-release "${TEST_TMP}/unsupported-os-release"
assert_eq 2 "${COMMAND_STATUS}" 'installer refuses an unsupported platform'
assert_contains "${COMMAND_OUTPUT}" 'Unsupported platform' 'unsupported-platform error is actionable'

printf 'ID=debian\nID_LIKE=debian\n' >"${TEST_TMP}/supported-os-release"
mkdir -p "${TEST_TMP}/install-mocks"
cat >"${TEST_TMP}/install-mocks/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl-called\n' >"${MOCK_CURL_MARKER}"
exit 2
EOF
cat >"${TEST_TMP}/install-mocks/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TEST_TMP}/install-mocks/curl" "${TEST_TMP}/install-mocks/apt-get"
run_status env PATH="${TEST_TMP}/install-mocks:${PATH}" \
  MOCK_CURL_MARKER="${TEST_TMP}/curl-called" bash \
  "${ROOT}/scripts/install-tailscale.sh" \
  --os-release "${TEST_TMP}/supported-os-release"
assert_eq 0 "${COMMAND_STATUS}" 'installer defaults to a plan-only result'
if [[ ! -e ${TEST_TMP}/curl-called ]]; then
  pass_test 'installer does not download without --apply'
else
  fail_test 'installer invoked curl without --apply'
fi

mkdir -p "${TEST_TMP}/install-warning-mocks"
cat >"${TEST_TMP}/install-warning-mocks/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${TEST_TMP}/install-warning-mocks/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${TEST_TMP}/install-warning-mocks/tailscale" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${TEST_TMP}/install-warning-mocks/"*
run_status env PATH="${TEST_TMP}/install-warning-mocks:${PATH}" bash \
  "${ROOT}/scripts/install-tailscale.sh" \
  --os-release "${TEST_TMP}/supported-os-release"
assert_eq 1 "${COMMAND_STATUS}" 'installer non-fatal verification warning maps to exit 1'

mkdir -p "${TEST_TMP}/dns-mocks"
cat >"${TEST_TMP}/dns-mocks/dig" <<'EOF'
#!/usr/bin/env bash
if [[ ${MOCK_DNS_STATE:-pass} == fail ]]; then
  exit 1
fi
blocked=false
for argument in "$@"; do
  [[ ${argument} == blocked.test ]] && blocked=true
done
if [[ ${blocked} == true && ${MOCK_DNS_STATE:-pass} == blocked ]]; then
  printf ';; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 1\n'
elif [[ ${blocked} == true && ${MOCK_DNS_STATE:-pass} == inconclusive ]]; then
  printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n'
  printf 'blocked.test. 60 IN A 203.0.113.8\n'
else
  printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n'
  printf 'example.com. 60 IN A 203.0.113.7\n'
fi
EOF
chmod +x "${TEST_TMP}/dns-mocks/dig"
server_address="100.$((64 + 6)).$((2 - 1)).$((1 + 1))"

run_status env PATH="${TEST_TMP}/dns-mocks:${PATH}" MOCK_DNS_STATE=blocked \
  bash "${ROOT}/scripts/verify-dns.sh" "${server_address}" \
  --blocked-domain blocked.test
assert_eq 0 "${COMMAND_STATUS}" 'verify-dns mocked PASS maps to exit 0'

run_status env PATH="${TEST_TMP}/dns-mocks:${PATH}" MOCK_DNS_STATE=inconclusive \
  bash "${ROOT}/scripts/verify-dns.sh" "${server_address}" \
  --blocked-domain blocked.test
assert_eq 1 "${COMMAND_STATUS}" 'verify-dns mocked WARN maps to exit 1'

run_status env PATH="${TEST_TMP}/dns-mocks:${PATH}" MOCK_DNS_STATE=fail \
  bash "${ROOT}/scripts/verify-dns.sh" "${server_address}"
assert_eq 2 "${COMMAND_STATUS}" 'verify-dns mocked FAIL maps to exit 2'
assert_contains "${COMMAND_OUTPUT}" '#critical-interface-listening-behavior' \
  'verify-dns failure links the probable listening-mode cause'

mkdir -p "${TEST_TMP}/limited-path"
cat >"${TEST_TMP}/limited-path/dirname" <<'EOF'
#!/usr/bin/bash
/usr/bin/dirname "$@"
EOF
cat >"${TEST_TMP}/limited-path/sed" <<'EOF'
#!/usr/bin/bash
/usr/bin/sed "$@"
EOF
chmod +x "${TEST_TMP}/limited-path/dirname" "${TEST_TMP}/limited-path/sed"
run_status env PATH="${TEST_TMP}/limited-path" /usr/bin/bash \
  "${ROOT}/scripts/verify-dns.sh" "${server_address}"
assert_eq 2 "${COMMAND_STATUS}" 'verify-dns reports missing dependencies as FAIL'

mkdir -p "${TEST_TMP}/health-mocks"
cat >"${TEST_TMP}/health-mocks/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${MOCK_HEALTH_STATE:-pass} == fail && $* == *pihole-FTL* ]]; then
  exit 3
fi
exit 0
EOF
cat >"${TEST_TMP}/health-mocks/tailscale" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  status)
    printf '%s\n' '{"BackendState":"Running","Self":{"Online":true,"KeyExpiry":"2099-01-01T00:00:00Z"}}'
    ;;
  ip)
    printf '100.%s.%s.%s\n' 70 1 2
    ;;
esac
EOF
cat >"${TEST_TMP}/health-mocks/pihole-FTL" <<'EOF'
#!/usr/bin/env bash
printf 'Pi-hole FTL v6.7\n'
EOF
cat >"${TEST_TMP}/health-mocks/ss" <<'EOF'
#!/usr/bin/env bash
printf 'UNCONN 0 0 100.%s.%s.%s:53 0.0.0.0:*\n' 70 1 2
EOF
cat >"${TEST_TMP}/health-mocks/ip" <<'EOF'
#!/usr/bin/env bash
printf '1: tailscale0 inet 100.%s.%s.%s/32 scope global tailscale0\n' 70 1 2
EOF
cat >"${TEST_TMP}/health-mocks/dig" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *+short* ]]; then
  printf '203.0.113.7\n'
else
  printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n'
  printf 'example.com. 60 IN A 203.0.113.7\n'
fi
EOF
cat >"${TEST_TMP}/health-mocks/pihole" <<'EOF'
#!/usr/bin/env bash
printf 'Blocking is enabled\n'
EOF
cat >"${TEST_TMP}/health-mocks/df" <<'EOF'
#!/usr/bin/env bash
if [[ ${MOCK_HEALTH_STATE:-pass} == warn ]]; then
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nmock 100 95 5 95%% /\n'
else
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nmock 100 50 50 50%% /\n'
fi
EOF
chmod +x "${TEST_TMP}/health-mocks/"*
touch "${TEST_TMP}/gravity.db"

run_status env PATH="${TEST_TMP}/health-mocks:${PATH}" MOCK_HEALTH_STATE=pass \
  bash "${ROOT}/scripts/health-check.sh" --server "${server_address}" \
  --gravity-database "${TEST_TMP}/gravity.db"
assert_eq 0 "${COMMAND_STATUS}" 'health-check mocked PASS maps to exit 0'

run_status env PATH="${TEST_TMP}/health-mocks:${PATH}" MOCK_HEALTH_STATE=warn \
  bash "${ROOT}/scripts/health-check.sh" --server "${server_address}" \
  --gravity-database "${TEST_TMP}/gravity.db"
assert_eq 1 "${COMMAND_STATUS}" 'health-check mocked WARN maps to exit 1'

run_status env PATH="${TEST_TMP}/health-mocks:${PATH}" MOCK_HEALTH_STATE=fail \
  bash "${ROOT}/scripts/health-check.sh" --server "${server_address}" \
  --gravity-database "${TEST_TMP}/gravity.db"
assert_eq 2 "${COMMAND_STATUS}" 'health-check mocked FAIL maps to exit 2'

mkdir -p "${ROOT}/evidence"
redaction_file="${ROOT}/evidence/redaction-test.tmp"
tailnet_value="node.example-tailnet.t"'s.net'
printf '%s %s\n' "${server_address}" "${tailnet_value}" | \
  bash -c 'source "$1"; write_redacted_file "$2"' _ \
  "${ROOT}/scripts/lib/common.sh" "${redaction_file}"
redacted_content=$(<"${redaction_file}")
rm -f -- "${redaction_file}"
rmdir -- "${ROOT}/evidence" 2>/dev/null || true
if [[ ${redacted_content} != *"${server_address}"* && \
  ${redacted_content} != *"${tailnet_value}"* ]]; then
  pass_test 'evidence-file helper redacts Tailscale address and tailnet name'
else
  fail_test 'evidence-file helper leaked a private tailnet value'
fi

mkdir -p "${TEST_TMP}/pihole-mocks"
cat >"${TEST_TMP}/pihole-mocks/pihole-FTL" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  --version)
    printf 'Pi-hole FTL v6.7\n'
    ;;
  --teleporter)
    python3 - <<'PY'
import zipfile
with zipfile.ZipFile('mock-export.zip', 'w') as archive:
    archive.writestr('etc/pihole/pihole.toml', '[dns]\n')
PY
    ;;
esac
EOF
cat >"${TEST_TMP}/pihole-mocks/pihole" <<'EOF'
#!/usr/bin/env bash
printf 'Blocking is enabled\n'
EOF
cat >"${TEST_TMP}/pihole-mocks/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${TEST_TMP}/pihole-mocks/install" <<'EOF'
#!/usr/bin/env bash
destination=${!#}
mkdir -p -- "${destination}"
EOF
cat >"${TEST_TMP}/pihole-mocks/chmod" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${TEST_TMP}/pihole-mocks/id" <<'EOF'
#!/usr/bin/env bash
printf 'users pihole\n'
EOF
cat >"${TEST_TMP}/pihole-mocks/curl" <<'EOF'
#!/usr/bin/env bash
request=$*
cat >/dev/null || true
if [[ ${request} == *'/api/auth'* && ${request} != *'DELETE'* ]]; then
  printf '{"session":{"sid":"mock-session-id"}}\n200'
elif [[ ${request} == *'/api/teleporter'* ]]; then
  printf '{}\n200'
fi
EOF
chmod +x "${TEST_TMP}/pihole-mocks/"*

run_status env PATH="${TEST_TMP}/pihole-mocks:${PATH}" bash \
  "${ROOT}/scripts/backup-config.sh" --dry-run --output-dir "${ROOT}/test-backup"
assert_eq 2 "${COMMAND_STATUS}" 'backup refuses a destination inside the repository'

backup_output="${TEST_TMP}/backups"
mkdir -p "${backup_output}"
touch "${backup_output}/pihole-teleporter-20260101T000000Z.zip"
touch "${backup_output}/pihole-teleporter-20260102T000000Z.zip"
run_status env PATH="${TEST_TMP}/pihole-mocks:${PATH}" bash \
  "${ROOT}/scripts/backup-config.sh" --dry-run --retention 1 \
  --output-dir "${backup_output}"
assert_eq 0 "${COMMAND_STATUS}" 'backup dry-run without --prune succeeds'
assert_eq 2 "$(find "${backup_output}" -type f | wc -l | tr -d ' ')" \
  'backup does not prune without --prune'

run_status env PATH="${TEST_TMP}/pihole-mocks:${PATH}" bash \
  "${ROOT}/scripts/backup-config.sh" --dry-run --prune --retention 1 \
  --output-dir "${backup_output}"
assert_eq 0 "${COMMAND_STATUS}" 'backup prune dry-run succeeds'
assert_contains "${COMMAND_OUTPUT}" 'Would remove' 'backup prune dry-run lists removals'
assert_eq 2 "$(find "${backup_output}" -type f | wc -l | tr -d ' ')" \
  'backup prune dry-run removes nothing'

run_status env PATH="${TEST_TMP}/pihole-mocks:${PATH}" bash \
  "${ROOT}/scripts/backup-config.sh" --prune --retention 1 \
  --disk-free-percent 0 --output-dir "${backup_output}"
assert_eq 0 "${COMMAND_STATUS}" 'backup mocked create and authorized prune map to exit 0'
assert_eq 1 "$(find "${backup_output}" -maxdepth 1 -type f -name 'pihole-teleporter-*.zip' | wc -l | tr -d ' ')" \
  'backup prunes only after --prune authorization'

low_disk_output="${TEST_TMP}/low-disk-backups"
run_status env PATH="${TEST_TMP}/pihole-mocks:${TEST_TMP}/health-mocks:${PATH}" \
  MOCK_HEALTH_STATE=warn bash "${ROOT}/scripts/backup-config.sh" \
  --output-dir "${low_disk_output}"
assert_eq 1 "${COMMAND_STATUS}" 'backup created with mocked low disk maps to exit 1'

archive_v6="${TEST_TMP}/archive-v6.zip"
archive_v5="${TEST_TMP}/archive-v5.zip"
python3 - "${archive_v6}" "${archive_v5}" <<'PY'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('etc/pihole/pihole.toml', '[dns]\n')
    archive.writestr('etc/pihole/gravity.db', 'synthetic')
with zipfile.ZipFile(sys.argv[2], 'w') as archive:
    archive.writestr('etc/pihole/setupVars.conf', 'SYNTHETIC=true\n')
PY

curl_marker="${TEST_TMP}/restore-curl-called"
cat >"${TEST_TMP}/pihole-mocks/curl-marker" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >"${MOCK_CURL_MARKER}"
exit 2
EOF
chmod +x "${TEST_TMP}/pihole-mocks/curl-marker"
mkdir -p "${TEST_TMP}/restore-dry-mocks"
for command_name in pihole-FTL pihole systemctl; do
  ln -s "${TEST_TMP}/pihole-mocks/${command_name}" \
    "${TEST_TMP}/restore-dry-mocks/${command_name}"
done
ln -s "${TEST_TMP}/pihole-mocks/curl-marker" "${TEST_TMP}/restore-dry-mocks/curl"

run_status env PATH="${TEST_TMP}/restore-dry-mocks:${PATH}" \
  MOCK_CURL_MARKER="${curl_marker}" bash "${ROOT}/scripts/restore-config.sh" \
  --dry-run "${archive_v6}"
assert_eq 0 "${COMMAND_STATUS}" 'restore dry-run maps to exit 0'
if [[ ! -e ${curl_marker} ]]; then
  pass_test 'restore dry-run does not call the Pi-hole API'
else
  fail_test 'restore dry-run called the Pi-hole API'
fi

run_status env PATH="${TEST_TMP}/pihole-mocks:${PATH}" bash \
  "${ROOT}/scripts/restore-config.sh" --dry-run "${archive_v5}"
assert_eq 2 "${COMMAND_STATUS}" 'restore refuses a major-version mismatch'

run_status env PATH="${TEST_TMP}/pihole-mocks:${PATH}" bash \
  "${ROOT}/scripts/restore-config.sh" --dry-run \
  --force-version-mismatch "${archive_v5}"
assert_eq 0 "${COMMAND_STATUS}" 'restore mismatch override permits a dry-run'

# shellcheck disable=SC2016
run_status bash -c 'printf "%s\n" unit-test-value | env PATH="$1:$PATH" bash "$2" --apply --yes --password-stdin "$3"' \
  _ "${TEST_TMP}/pihole-mocks" "${ROOT}/scripts/restore-config.sh" "${archive_v6}"
assert_eq 0 "${COMMAND_STATUS}" 'restore mocked --apply --yes maps to exit 0'

# shellcheck disable=SC2016
run_status bash -c 'printf "%s\n" unit-test-value | env PATH="$1:$PATH" bash "$2" --apply --yes --password-stdin --force-version-mismatch "$3"' \
  _ "${TEST_TMP}/pihole-mocks" "${ROOT}/scripts/restore-config.sh" "${archive_v5}"
assert_eq 1 "${COMMAND_STATUS}" 'restore applied with mismatch warning maps to exit 1'

if rg -n --glob 'scripts/*.sh' --glob 'scripts/lib/*.sh' \
  -- '--auth-key|TS_AUTHKEY|TAILSCALE_AUTHKEY' "${ROOT}" >/dev/null; then
  fail_test 'scripts must not accept auth key arguments or environment variables'
else
  pass_test 'scripts do not accept auth key arguments or environment variables'
fi

if rg -n --glob 'scripts/*.sh' --glob 'scripts/lib/*.sh' \
  -- 'tailscale[[:space:]]+(set|up).*(key-expir|expiry)' "${ROOT}" >/dev/null; then
  fail_test 'scripts must not mutate Tailscale key expiration'
else
  pass_test 'scripts do not mutate Tailscale key expiration'
fi

if rg -n --glob 'scripts/*.sh' --glob 'scripts/lib/*.sh' \
  -- 'systemctl[[:space:]]+(enable|start).*pihole-tailscale-healthcheck\.timer' \
  "${ROOT}" >/dev/null; then
  fail_test 'scripts must not enable or start the health timer'
else
  pass_test 'scripts do not enable or start the health timer'
fi

python3 - "${ROOT}" <<'PY'
import re
import sys
from pathlib import Path
from urllib.parse import unquote

root = Path(sys.argv[1])
excluded = {'.git', 'prompts', 'evidence', 'backups', 'node_modules'}
markdown = [p for p in root.rglob('*.md') if not excluded.intersection(p.parts)]
failures = []

def slug(value):
    value = value.strip().lower().replace('`', '')
    value = re.sub(r'[^\w\- ]', '', value)
    return re.sub(r'\s+', '-', value)

for document in markdown:
    text = document.read_text(encoding='utf-8')
    for target in re.findall(r'(?<!!)\[[^]]+\]\(([^)]+)\)', text):
        target = target.strip().split()[0].strip('<>')
        if target.startswith(('http://', 'https://', 'mailto:')):
            continue
        path_part, _, anchor = target.partition('#')
        linked = document if not path_part else (document.parent / unquote(path_part)).resolve()
        if not linked.exists():
            failures.append(f'{document.relative_to(root)} -> missing {target}')
            continue
        if anchor and linked.suffix.lower() == '.md':
            headings = {
                slug(line.lstrip('#').strip())
                for line in linked.read_text(encoding='utf-8').splitlines()
                if re.match(r'^#{1,6} ', line)
            }
            if unquote(anchor).lower() not in headings:
                failures.append(f'{document.relative_to(root)} -> missing anchor {target}')

if failures:
    print('\n'.join(failures), file=sys.stderr)
    raise SystemExit(1)
PY
assert_eq 0 "$?" 'all internal Markdown links resolve'

python3 - "${ROOT}" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
excluded = {'.git', 'prompts', 'evidence', 'backups', 'node_modules'}
address = re.compile(r'\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b')
allowed = {'100.64.0.0', '100.100.100.100'}
failures = []
for path in root.rglob('*'):
    if not path.is_file() or excluded.intersection(path.parts):
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    for match in address.findall(text):
        if match not in allowed:
            failures.append(f'{path.relative_to(root)} contains prohibited address {match}')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    raise SystemExit(1)
PY
assert_eq 0 "$?" 'tracked-intended files contain no real Tailscale device address'

python3 - "${ROOT}" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
excluded = {'.git', 'prompts', 'evidence', 'backups', 'node_modules'}
tokens = set()
for path in root.rglob('*'):
    if not path.is_file() or excluded.intersection(path.parts):
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    tokens.update(re.findall(r'<[A-Z][A-Z0-9_]+>', text))
definitions = Path(root, 'docs', 'prerequisites.md').read_text(encoding='utf-8')
missing = sorted(token for token in tokens if f'| `{token}` |' not in definitions)
if missing:
    print('Undefined placeholders: ' + ', '.join(missing), file=sys.stderr)
    raise SystemExit(1)
PY
assert_eq 0 "$?" 'every placeholder is defined in prerequisites'

service_unit=$(<"${ROOT}/systemd/pihole-tailscale-healthcheck.service")
timer_unit=$(<"${ROOT}/systemd/pihole-tailscale-healthcheck.timer")
assert_contains "${service_unit}" 'User=root' 'health service runs under the documented account'
assert_contains "${service_unit}" 'SuccessExitStatus=1' 'systemd treats WARN as a completed check'
assert_contains "${service_unit}" '/usr/local/lib/pihole-tailscale/health-check.sh --quiet' \
  'health service uses the installed path and quiet mode'
assert_contains "${timer_unit}" 'OnCalendar=hourly' 'health timer runs hourly'
assert_contains "${timer_unit}" 'RandomizedDelaySec=600' 'health timer randomizes by 600 seconds'

required=(
  README.md LICENSE CHANGELOG.md ASSESSMENT.md FUTURE-UPGRADES.md
  COMPLETED-UPGRADES.md SECURITY.md docs/architecture.md docs/prerequisites.md
  docs/installation.md docs/pihole-configuration.md docs/tailscale-configuration.md
  docs/ios-configuration.md docs/testing.md docs/troubleshooting.md docs/security.md
  docs/maintenance.md docs/rollback.md docs/references.md
  docs/advanced/exit-node.md docs/advanced/subnet-routing.md
  docs/advanced/high-availability.md docs/advanced/multiple-pihole-servers.md
  scripts/lib/common.sh scripts/install-tailscale.sh scripts/verify-dns.sh
  scripts/health-check.sh scripts/backup-config.sh scripts/restore-config.sh
  tests/run-tests.sh systemd/pihole-tailscale-healthcheck.service
  systemd/pihole-tailscale-healthcheck.timer .github/workflows/quality.yml
  .github/dependabot.yml .editorconfig .gitattributes .gitignore
  .markdownlint-cli2.jsonc .shellcheckrc
)
missing=0
for required_path in "${required[@]}"; do
  if [[ ! -f ${ROOT}/${required_path} ]]; then
    printf 'FAIL: Required path missing: %s\n' "${required_path}" >&2
    missing=$((missing + 1))
  fi
done
assert_eq 0 "${missing}" 'required repository structure is complete'

python3 - "${ROOT}" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
bad = []
for pattern in ('scripts/**/*.sh', 'tests/**/*.sh'):
    for path in root.glob(pattern):
        if b'\r\n' in path.read_bytes():
            bad.append(str(path.relative_to(root)))
if bad:
    print('CRLF shell files: ' + ', '.join(bad), file=sys.stderr)
    raise SystemExit(1)
PY
assert_eq 0 "$?" 'shell files use LF line endings'

printf 'Tests run: %d; failures: %d\n' "${TESTS_RUN}" "${TESTS_FAILED}"
if ((TESTS_FAILED > 0)); then
  exit 1
fi
exit 0
