#!/usr/bin/env bash
set -euo pipefail

# Exit contract:
# 0 installation plan printed, installed, or already present and healthy
# 1 installed with a non-fatal warning
# 2 unsupported platform, installation failure, or verification failure
# 64 invalid usage

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

APPLY=false
OS_RELEASE=/etc/os-release
HTTP_TIMEOUT=15
INSTALLER_URL=https://tailscale.com/install.sh

usage() {
  cat <<'EOF'
Usage: install-tailscale.sh [--apply] [--timeout SECONDS] [--os-release FILE]

Prints a Tailscale installation plan by default. --apply downloads the current
official Linux installer to a temporary file and runs it. Enrollment remains a
manual step and DNS acceptance is disabled during enrollment.

Options:
  --apply              Install and verify Tailscale.
  --timeout SECONDS    HTTP timeout. Default: 15.
  --os-release FILE    Alternate os-release file for validation or testing.
  -h, --help           Show this help.

Exit codes:
  0  Plan printed, installed, or already present and healthy.
  1  Installed with a non-fatal warning.
  2  Unsupported platform, install failure, or verification failure.
  64 Invalid arguments.
EOF
}

while (($#)); do
  case $1 in
    --apply)
      APPLY=true
      shift
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      HTTP_TIMEOUT=$2
      shift 2
      ;;
    --os-release)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      OS_RELEASE=$2
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

if [[ ! ${HTTP_TIMEOUT} =~ ^[1-9][0-9]*$ ]]; then
  fail "Timeout must be a positive integer."
  exit "${EXIT_USAGE}"
fi

if [[ ! -r ${OS_RELEASE} ]]; then
  fail "Cannot read operating-system metadata: ${OS_RELEASE}"
  exit "${EXIT_FAIL}"
fi

os_id=$(sed -nE 's/^ID="?([^" ]+)"?$/\1/p' "${OS_RELEASE}")
os_like=$(sed -nE 's/^ID_LIKE="?([^" ]+)"?$/\1/p' "${OS_RELEASE}")
case " ${os_id} ${os_like} " in
  *" debian "*|*" ubuntu "*|*" raspbian "*) ;;
  *)
    fail "Unsupported platform '${os_id:-unknown}'. Use the official Tailscale instructions for this operating system."
    exit "${EXIT_FAIL}"
    ;;
esac

if command -v apt-get >/dev/null 2>&1; then
  package_manager=apt-get
else
  fail "Supported Debian-family platform detected, but the required apt-get package manager is unavailable."
  exit "${EXIT_FAIL}"
fi

if command -v tailscale >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet tailscaled; then
    if ! tailscale version >/dev/null 2>&1; then
      warn "tailscaled is active, but the Tailscale client version check failed."
      emit_line "Manual enrollment, if needed: sudo tailscale up --accept-dns=false"
      exit "${EXIT_WARN}"
    fi
    pass "Tailscale is already installed, the client responds, and tailscaled is active."
    emit_line "Manual enrollment, if needed: sudo tailscale up --accept-dns=false"
    exit "${EXIT_PASS}"
  fi
  fail "Tailscale is installed, but tailscaled is not active. Inspect the service before reinstalling."
  exit "${EXIT_FAIL}"
fi

emit_line "PLAN: Download ${INSTALLER_URL} to a temporary file and run it on ${os_id} using ${package_manager}."
emit_line "PLAN: Verify the tailscale binary and tailscaled service."
emit_line "PLAN: Enrollment remains manual: sudo tailscale up --accept-dns=false"

if [[ ${APPLY} != true ]]; then
  pass "No changes made. Re-run with --apply after reviewing the plan."
  exit "${EXIT_PASS}"
fi

require_root || exit "${EXIT_FAIL}"
require_command curl || exit "${EXIT_FAIL}"
require_command systemctl || exit "${EXIT_FAIL}"

temp_dir=$(mktemp -d)
cleanup() {
  rm -f -- "${temp_dir}/install.sh"
  rmdir -- "${temp_dir}" 2>/dev/null || true
}
trap cleanup EXIT

if ! run_with_timeout "${HTTP_TIMEOUT}" curl --fail --silent --show-error \
  --location --proto '=https' --tlsv1.2 --output "${temp_dir}/install.sh" \
  "${INSTALLER_URL}"; then
  fail "Tailscale installer download failed."
  exit "${EXIT_FAIL}"
fi

if [[ ! -s ${temp_dir}/install.sh ]]; then
  fail "Downloaded installer is empty."
  exit "${EXIT_FAIL}"
fi

if ! /bin/sh "${temp_dir}/install.sh"; then
  fail "The official Tailscale installer failed."
  exit "${EXIT_FAIL}"
fi

if ! command -v tailscale >/dev/null 2>&1; then
  fail "Installation completed without a tailscale binary on PATH."
  exit "${EXIT_FAIL}"
fi

if ! systemctl is-active --quiet tailscaled; then
  fail "Tailscale installed, but tailscaled is not active."
  exit "${EXIT_FAIL}"
fi

if ! tailscale version >/dev/null 2>&1; then
  warn "Tailscale installed and tailscaled is active, but the client version check failed."
  emit_line "Manual enrollment: sudo tailscale up --accept-dns=false"
  exit "${EXIT_WARN}"
fi

pass "Tailscale installed and tailscaled is active."
emit_line "Manual enrollment: sudo tailscale up --accept-dns=false"
