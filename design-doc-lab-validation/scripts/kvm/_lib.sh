# _lib.sh: shared functions for the lab harness scripts (sourced, never executed).
# shellcheck shell=bash
set -euo pipefail

die()   { echo "$(basename "$0"): $*" >&2; exit 1; }
usage() { echo "usage: $(basename "$0") $*" >&2; exit 2; }

# Lab-only shortcut: guests get new host keys on every clone, so host-key checks are off.
# shellcheck disable=SC2034  # used by the scripts that source this file
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
          -o ConnectTimeout=5 -o BatchMode=yes)

_env_file() {
  if [ -n "${LAB_ENV:-}" ]; then echo "$LAB_ENV"
  elif [ -n "${LAB_DIR:-}" ]; then echo "$LAB_DIR/lab.env"; fi
}

# _default_max_gb: default MAX_RUNNING_GB from host RAM: MemTotal in whole GiB, minus 6 when
# above 8 GiB, minus 2 at 8 GiB or less, floor 4; 24 when the meminfo file cannot be read.
# LAB_MEMINFO (default /proc/meminfo) exists so tests can supply a fake file.
_default_max_gb() {
  local kb gb
  kb=$(awk '/^MemTotal:/ { print $2 }' "${LAB_MEMINFO:-/proc/meminfo}" 2>/dev/null) || kb=""
  if [ -z "$kb" ]; then echo 24; return 0; fi
  gb=$((kb / 1048576))
  if [ "$gb" -gt 8 ]; then gb=$((gb - 6)); else gb=$((gb - 2)); fi
  if [ "$gb" -lt 4 ]; then gb=4; fi
  echo "$gb"
}

_defaults() {
  EVID=${EVID:-$LAB_DIR/evidence}; IMG=${IMG:-/var/lib/libvirt/images}
  LAB_USER=${LAB_USER:-ubuntu}; SECRETS=${SECRETS:-$LAB_DIR/secrets}; VM_PREFIX=${VM_PREFIX:-}
  CODE=${CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}; VARS=${VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
  SCSI_MODEL=${SCSI_MODEL:-virtio-scsi}; NIC_MODEL=${NIC_MODEL:-virtio}
  MAX_RUNNING_GB=${MAX_RUNNING_GB:-$(_default_max_gb)}; DEPLOY=${DEPLOY:-http://192.168.122.1}
  PASSFILE=${PASSFILE:-}; VM_USER=${VM_USER:-}; NGINX_LOG=${NGINX_LOG:-}
  export LAB_DIR EVID IMG LAB_USER SECRETS VM_PREFIX CODE VARS SCSI_MODEL NIC_MODEL \
         MAX_RUNNING_GB DEPLOY PASSFILE VM_USER NGINX_LOG
}

# load_env: source the campaign's lab.env (exit 2 if missing) and apply defaults.
load_env() {
  local f; f=$(_env_file)
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "$(basename "$0"): no lab.env (set LAB_ENV=path or LAB_DIR=dir)" >&2; exit 2
  fi
  # shellcheck disable=SC1090  # path chosen at run time
  source "$f"
  if [ -z "${LAB_DIR:-}" ]; then echo "$(basename "$0"): $f must set LAB_DIR" >&2; exit 2; fi
  export LAB_ENV=$f
  _defaults
  mkdir -p "$EVID/logs" "$EVID/state" "$EVID/timing"
}

# load_env_optional: load_env if a lab.env exists, else defaults with LAB_DIR=$PWD.
load_env_optional() {
  local f; f=$(_env_file)
  if [ -n "$f" ] && [ -f "$f" ]; then load_env; else LAB_DIR=${LAB_DIR:-$PWD}; _defaults; fi
}

# require_prefix NAME: refuse to manage VMs outside this campaign.
require_prefix() {
  if [ -z "$VM_PREFIX" ]; then die "VM_PREFIX is empty in lab.env; refusing to manage VMs without a prefix"; fi
  case "$1" in "$VM_PREFIX"*) ;; *) die "'$1' does not start with VM_PREFIX '$VM_PREFIX'" ;; esac
}
