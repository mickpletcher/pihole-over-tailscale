#!/usr/bin/env bash
set -euo pipefail

# Exit contract:
# 0 archive created and verified, or dry-run completed
# 1 archive created with a non-fatal warning such as low disk space
# 2 backup or archive verification failed
# 64 invalid arguments

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR=${XDG_STATE_HOME:-${HOME}/.local/state}/pihole-tailscale-backups
RETENTION=7
PRUNE=false
DRY_RUN=false
DISK_FREE_PERCENT=10

usage() {
  cat <<'EOF'
Usage: backup-config.sh [options]

Creates a verified Pi-hole v6 Teleporter archive outside any Git worktree.
Archive creation is the requested operation. Retention deletion occurs only
when --prune is supplied. --dry-run creates or deletes nothing.

Options:
  --output-dir DIRECTORY  Archive directory. Default:
                          ${XDG_STATE_HOME:-$HOME/.local/state}/pihole-tailscale-backups
  --retention COUNT       Archives to retain. Default: 7.
  --prune                 Delete archives beyond the retention count.
  --dry-run               Print create and prune actions without changing files.
  --disk-free-percent N   Low-space warning threshold. Default: 10.
  -h, --help              Show this help.

Exit codes:
  0  Archive created and verified, or dry-run completed.
  1  Archive created with a non-fatal warning.
  2  Backup or verification failed.
  64 Invalid arguments.
EOF
}

while (($#)); do
  case $1 in
    --output-dir)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      OUTPUT_DIR=$2
      shift 2
      ;;
    --retention)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      RETENTION=$2
      shift 2
      ;;
    --prune)
      PRUNE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --disk-free-percent)
      [[ $# -ge 2 ]] || { usage >&2; exit "${EXIT_USAGE}"; }
      DISK_FREE_PERCENT=$2
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

if [[ ! ${RETENTION} =~ ^[1-9][0-9]*$ ]] || \
  [[ ! ${DISK_FREE_PERCENT} =~ ^[0-9]+$ ]] || ((DISK_FREE_PERCENT > 100)); then
  fail "Retention must be positive and disk threshold must be between 0 and 100."
  exit "${EXIT_USAGE}"
fi
if [[ -z ${OUTPUT_DIR} ]]; then
  fail "Output directory cannot be empty."
  exit "${EXIT_USAGE}"
fi

for dependency in df find git id pihole-FTL realpath sort unzip; do
  require_command "${dependency}" || true
done
if ((FAIL_COUNT > 0)); then
  exit "${EXIT_FAIL}"
fi

resolved_output=$(realpath -m -- "${OUTPUT_DIR}")
case "${resolved_output}/" in
  "${REPOSITORY_ROOT}/"*)
    fail "Backup output must be outside this repository: ${resolved_output}"
    exit "${EXIT_FAIL}"
    ;;
esac

existing_parent=${resolved_output}
while [[ ! -e ${existing_parent} && ${existing_parent} != / ]]; do
  existing_parent=$(dirname -- "${existing_parent}")
done
if worktree_root=$(git -C "${existing_parent}" rev-parse --show-toplevel 2>/dev/null); then
  fail "Backup output is inside a Git worktree: ${worktree_root}"
  exit "${EXIT_FAIL}"
fi

ftl_version_output=$(pihole-FTL --version 2>/dev/null || true)
ftl_version=$(extract_version <<<"${ftl_version_output}" || true)
if [[ -z ${ftl_version} ]]; then
  fail "Could not determine the installed Pi-hole FTL version."
  exit "${EXIT_FAIL}"
fi
if [[ ${ftl_version%%.*} != 6 ]]; then
  fail "Pi-hole v${ftl_version%%.*} is unsupported. Upgrade to the documented Pi-hole v6 baseline before using this wrapper."
  exit "${EXIT_FAIL}"
fi

emit_line "PLAN: Create a Pi-hole v6 Teleporter archive in ${resolved_output}."
emit_line "NOTICE: The archive contains private configuration and browsing-related data. Transfer and retain it securely."
emit_line "NOTICE: This wrapper does not capture Tailscale state, node keys, auth material, API tokens, or credentials outside Pi-hole's supported archive."
if [[ ${PRUNE} == true ]]; then
  emit_line "PLAN: Retain the newest ${RETENTION} repository-created archives and remove older ones."
else
  emit_line "PLAN: Retention deletion is disabled. Pass --prune to authorize it."
fi

list_prune_candidates() {
  local directory=$1
  local reserved_new=${2:-0}
  local existing_to_keep=$((RETENTION - reserved_new))
  mapfile -t archives < <(find "${directory}" -maxdepth 1 -type f \
    -name 'pihole-teleporter-*.zip' -printf '%T@ %p\n' 2>/dev/null | \
    sort -rn | cut -d' ' -f2-)
  if ((existing_to_keep < 0)); then
    existing_to_keep=0
  fi
  if ((${#archives[@]} <= existing_to_keep)); then
    return
  fi
  printf '%s\n' "${archives[@]:existing_to_keep}"
}

if [[ ${DRY_RUN} == true ]]; then
  if [[ ${PRUNE} == true && -d ${resolved_output} ]]; then
    prune_candidates=$(list_prune_candidates "${resolved_output}" 1)
    if [[ -n ${prune_candidates} ]]; then
      while IFS= read -r archive; do
        emit_line "DRY-RUN: Would remove ${archive}"
      done <<<"${prune_candidates}"
    else
      pass "No archives currently exceed retention."
    fi
  fi
  pass "Dry-run complete. No archive was created or removed."
  exit "${EXIT_PASS}"
fi

if [[ ${EUID} -ne 0 ]] && ! id -nG | tr ' ' '\n' | grep -qx pihole; then
  fail "Backup requires root or membership in the pihole group. Run with sudo or grant the documented group access."
  exit "${EXIT_FAIL}"
fi

install -d -m 0700 -- "${resolved_output}"
chmod 0700 -- "${resolved_output}"

available_percent=$(df -P "${resolved_output}" | awk 'NR==2 {gsub(/%/, "", $5); print 100-$5}')
if [[ ${available_percent} =~ ^[0-9]+$ ]] && ((available_percent < DISK_FREE_PERCENT)); then
  warn "Backup filesystem has ${available_percent}% free, below the ${DISK_FREE_PERCENT}% threshold."
fi

temp_dir=$(mktemp -d "${resolved_output}/.backup.XXXXXX")
# shellcheck disable=SC2317,SC2329
cleanup() {
  rm -f -- "${temp_dir}"/*.zip 2>/dev/null || true
  rmdir -- "${temp_dir}" 2>/dev/null || true
}
trap cleanup EXIT

if ! (cd -- "${temp_dir}" && pihole-FTL --teleporter >/dev/null); then
  fail "Pi-hole Teleporter export failed."
  exit "${EXIT_FAIL}"
fi

mapfile -t created_archives < <(find "${temp_dir}" -maxdepth 1 -type f -name '*.zip' -print)
if ((${#created_archives[@]} != 1)) || [[ ! -s ${created_archives[0]:-} ]]; then
  fail "Teleporter did not create exactly one nonempty ZIP archive."
  exit "${EXIT_FAIL}"
fi
if ! unzip -tqq "${created_archives[0]}"; then
  fail "Teleporter archive failed ZIP integrity verification."
  exit "${EXIT_FAIL}"
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
destination=${resolved_output}/pihole-teleporter-${timestamp}.zip
if [[ -e ${destination} ]]; then
  fail "Refusing to overwrite an existing archive: ${destination}"
  exit "${EXIT_FAIL}"
fi
mv -- "${created_archives[0]}" "${destination}"
chmod 0600 -- "${destination}"
pass "Created and verified ${destination}"
emit_line "ARCHIVE: ${destination}"

if [[ ${PRUNE} == true ]]; then
  prune_candidates=$(list_prune_candidates "${resolved_output}")
  if [[ -n ${prune_candidates} ]]; then
    while IFS= read -r archive; do
      rm -f -- "${archive}"
      emit_line "PRUNED: ${archive}"
    done <<<"${prune_candidates}"
  else
    pass "No archives exceed retention."
  fi
fi

if ((WARN_COUNT > 0)); then
  exit "${EXIT_WARN}"
fi
exit "${EXIT_PASS}"
