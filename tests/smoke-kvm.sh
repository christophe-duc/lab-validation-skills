#!/usr/bin/env bash
# smoke-kvm.sh [--reduced] BASE: exercise the harness on a lab host with throwaway hx-* VMs.
# BASE: local Ubuntu cloud image (.img/.qcow2/.vmdk) or https URL of a .img (checked against
# SHA256SUMS in the same directory). Needs ~/lab/hx-smoke/bin = scripts/kvm, and the user in
# the libvirt group. Touches only hx-* VMs, $IMG/hx-* and ~/lab/hx-smoke; cleans them up at
# the end. Report: ~/lab/hx-smoke/smoke-report.md. --reduced: bootstrap, clone, ssh, sudo,
# env-dump, scrub only (fresh hosts).
# MAX_RUNNING_GB (memory guard): lab.env gets a value only if one is set in the environment;
# otherwise the harness default applies (_lib.sh: host RAM in GiB minus 6, minus 2 on hosts
# of 8 GiB or less, floor 4). One rule, no second derivation here.
set -uo pipefail
REDUCED=no
if [ "${1:-}" = --reduced ]; then REDUCED=yes; shift; fi
if [ $# -ne 1 ]; then echo "usage: smoke-kvm.sh [--reduced] BASE" >&2; exit 2; fi
SRC=$1
export LAB_DIR=$HOME/lab/hx-smoke
BIN=$LAB_DIR/bin; export PATH=$BIN:$PATH
[ -x "$BIN/vm-create" ] || { echo "copy scripts/kvm to $BIN first" >&2; exit 2; }
mkdir -p "$LAB_DIR/secrets" "$LAB_DIR/evidence/logs"; chmod 700 "$LAB_DIR/secrets"
if [ ! -s "$LAB_DIR/secrets/vm-pass" ]; then (umask 077; openssl rand -base64 18 > "$LAB_DIR/secrets/vm-pass"); fi
cat > "$LAB_DIR/lab.env" <<EOF
LAB_DIR=$LAB_DIR
VM_PREFIX=hx-
LAB_USER=smoke
PASSFILE=$LAB_DIR/secrets/vm-pass
EOF
if [ -n "${MAX_RUNNING_GB:-}" ]; then echo "MAX_RUNNING_GB=$MAX_RUNNING_GB" >> "$LAB_DIR/lab.env"; fi
export LAB_ENV=$LAB_DIR/lab.env
IMG=/var/lib/libvirt/images
REPORT=$LAB_DIR/smoke-report.md
FAILS=0
{ echo "# harness smoke $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname) (reduced=$REDUCED)"; echo
  echo "| step | result | detail |"; echo "|---|---|---|"; } > "$REPORT"

run() {   # run STEP FUNCTION: log to evidence, one row in the report
  local log=$LAB_DIR/evidence/logs/smoke-$1.txt rc last
  echo "== $1"
  "$2" > "$log" 2>&1; rc=$?
  last=$(grep -v '^[[:space:]]*$' "$log" | tail -1 | tr '|' '/' | cut -c1-110)
  if [ $rc -eq 0 ]; then echo "| $1 | PASS | $last |" >> "$REPORT"
  else echo "| $1 | FAIL (rc $rc) | $last |" >> "$REPORT"; FAILS=$((FAILS + 1)); fi
  echo "   rc=$rc $last"
}

mkseed() {   # mkseed VM: NoCloud seed with user smoke (password from PASSFILE, sudo with password)
  local t; t=$(mktemp -d)
  local hash; hash=$(openssl passwd -6 -stdin < "$LAB_DIR/secrets/vm-pass")
  printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$1" "$(date +%s)" "$1" > "$t/meta-data"
  cat > "$t/user-data" <<EOF
#cloud-config
users:
  - name: smoke
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: false
    passwd: "$hash"
    sudo: "ALL=(ALL) ALL"
    ssh_authorized_keys: ["$(cat "$HOME/.ssh/id_ed25519.pub")"]
EOF
  genisoimage -quiet -output "$t.iso" -volid cidata -joliet -rock "$t"
  sudo cp "$t.iso" "$IMG/hx-seed-$1.iso"; sudo chmod 600 "$IMG/hx-seed-$1.iso"; rm -rf "$t" "$t.iso"
}

shutoff() {   # shutoff VM: graceful, then destroy after 60 s
  virsh shutdown "$1" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do [ "$(virsh domstate "$1" 2>/dev/null)" = "shut off" ] && return 0; sleep 2; done
  virsh destroy "$1" >/dev/null 2>&1 || true
}

s_bootstrap() { host-bootstrap && host-bootstrap; }          # second run must also succeed (idempotent)

s_base() {
  local f=$SRC
  if [[ $SRC == https://* ]]; then
    f=$LAB_DIR/${SRC##*/}
    curl -fsSL -o "$f" -C - "$SRC" || curl -fsSL -o "$f" "$SRC" || return 1
    (cd "$LAB_DIR" && curl -fsSL "${SRC%/*}/SHA256SUMS" | grep -E " \*?${SRC##*/}$" | sha256sum -c -) || return 1
  fi
  sudo qemu-img convert -O qcow2 "$f" "$IMG/hx-base.qcow2" && sudo qemu-img resize -q "$IMG/hx-base.qcow2" 10G \
    && sudo chmod 0444 "$IMG/hx-base.qcow2" && echo "base ready: $IMG/hx-base.qcow2"
}

s_clone() { mkseed hx-a && vm-clone hx-a "$IMG/hx-base.qcow2" "$IMG/hx-seed-hx-a.iso" && wait-ready hx-a 600; }

s_ssh() { [ "$(vm-ssh hx-a hostname </dev/null)" = hx-a ] && echo "vm-ssh: hostname hx-a"; }

s_sudo() {
  [ "$(vm-sudo hx-a 'id -u')" = 0 ] || return 1
  if vm-ssh hx-a 'sudo -n true' </dev/null 2>/dev/null; then echo "sudo -n worked: password not required?"; return 1; fi
  echo "vm-sudo: root via password file; sudo -n refused as expected"
}

s_snap() {
  vm-snap snap hx-a base1 || return 1
  local err   # reusing a snapshot name must fail because the snapshot exists, not for any other reason
  if err=$(vm-snap snap hx-a base1 2>&1 >/dev/null); then echo "snapshot name reused"; return 1; fi
  case "$err" in *exists*) echo "name reuse refused: $err" ;; *) echo "wrong failure on name reuse: $err"; return 1 ;; esac
  virsh start hx-a >/dev/null && wait-ready hx-a 300 --no-cloud-init || return 1
  vm-sudo hx-a 'touch /root/hx-marker && test -f /root/hx-marker' || return 1
  shutoff hx-a
  vm-snap restore hx-a base1 || return 1
  virsh start hx-a >/dev/null && wait-ready hx-a 300 --no-cloud-init || return 1
  vm-sudo hx-a 'test ! -e /root/hx-marker' && echo "restore removed the marker"
}

s_console() {
  local n; n=smoke$(date +%s)   # unique per run: old logs in the evidence dir cannot satisfy the check
  python3 "$BIN/labconsole.py" expect hx-a "$n" 'login:' --timeout 40 --enter || return 1
  local f
  for f in "$LAB_DIR"/evidence/logs/console-$n-*.log "$LAB_DIR"/evidence/logs/console-$n-*.txt; do
    [ -s "$f" ] || { echo "missing or empty console log: $f"; return 1; }
  done
  echo "console logs (.log + .txt) written for $n"
}

s_ro() {
  shutoff hx-a
  printf 'cat /etc/hostname\nls /nonexistent\ncat /etc/machine-id\n' > "$LAB_DIR/ro-cmds"
  local out; out=$(ro-inspect "$IMG/hx-a.qcow2" "$LAB_DIR/ro-cmds" 2>&1)
  echo "$out"
  grep -qx hx-a <<<"$out" || { echo "hostname line hx-a missing"; return 1; }
  # the machine-id (32 hex chars) must be printed AFTER the failing ls: a tool that aborts at the first error fails here
  local errl idl
  errl=$(grep -n nonexistent <<<"$out" | tail -1 | cut -d: -f1)
  idl=$(grep -nE '^[0-9a-f]{32}$' <<<"$out" | tail -1 | cut -d: -f1)
  if [ -z "$errl" ] || [ -z "$idl" ] || [ "$idl" -le "$errl" ]; then
    echo "machine-id not read after the failing command (error line '${errl:-none}', machine-id line '${idl:-none}')"; return 1
  fi
  echo "ro-inspect read the hostname and the machine-id past a failing command"
}

s_sb() {
  mkseed hx-sb && SB=yes TPM=yes vm-clone hx-sb "$IMG/hx-base.qcow2" "$IMG/hx-seed-hx-sb.iso" && wait-ready hx-sb 600 || return 1
  local out
  out=$(vm-ssh hx-sb 'od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c | awk "{print \$NF}"; ls /dev/tpm0' </dev/null)
  echo "$out"
  case "$out" in "1"*"/dev/tpm0"*) echo "Secure Boot enabled, TPM present" ;; *) return 1 ;; esac
}

s_memguard() {
  local out rc
  out=$(MEM=999999 vm-create hx-big --size 1 --kernel /nonexistent --initrd /nonexistent 2>&1); rc=$?
  echo "$out"
  [ $rc -eq 1 ] && case "$out" in *"memory guard"*) echo "memory guard refused"; return 0 ;; esac
  return 1
}

s_prockill() {
  sleep 7777 & local p=$!
  proc-kill 'sleep 7777'; sleep 0.5
  if kill -0 "$p" 2>/dev/null; then kill "$p"; return 1; fi
  echo "proc-kill killed the target and not itself"
}

s_envdump() {
  local out f; out=$(env-dump "$IMG/hx-base.qcow2"); f=${out#wrote }
  grep -q '^instance-type ' "$f" && grep -q 'hx-base.qcow2' "$f" && echo "$out"
}

s_scrub() {
  # this lab.env has a secrets dir, so the scan must say a plain "is clean", not "(secrets not checked)"
  local sc; sc=$(scrub-evidence "$LAB_DIR/evidence") || { echo "$sc"; return 1; }
  echo "$sc"
  case "$sc" in *"secrets not checked"*) echo "secrets dir was not used"; return 1 ;; esac
  local t out rc hit; t=$(mktemp -d); cp "$LAB_DIR/secrets/vm-pass" "$t/leak.txt"
  out=$(scrub-evidence "$t" 2>&1); rc=$?
  rm -rf "$t"
  hit=$(grep -m1 '^HIT secret' <<<"$out" || true)
  if [ "$rc" -ne 1 ] || [ -z "$hit" ]; then echo "planted secret not reported as expected (rc $rc, want 1 and a HIT secret line): $out"; return 1; fi
  echo "$hit"
  echo "smoke evidence clean; planted secret found (rc 1, HIT secret)"
}

cleanup() {
  for d in $(virsh list --all --name 2>/dev/null | grep '^hx-'); do
    virsh destroy "$d" >/dev/null 2>&1 || true
    virsh undefine "$d" --nvram >/dev/null 2>&1 || virsh undefine "$d" >/dev/null 2>&1 || true
  done
  sudo sh -c "rm -f $IMG/hx-*.qcow2 $IMG/hx-*.iso"
  sudo rm -rf "$LAB_DIR/snaps"
  echo "removed hx-* VMs, disks, seeds, snapshots"
}

run bootstrap s_bootstrap
run base s_base
run clone s_clone
run ssh s_ssh
# shellcheck disable=SC2033  # false positive: `run` is our function, "sudo" is its STEP name
run sudo s_sudo
if [ "$REDUCED" = no ]; then
  run snap s_snap
  run console s_console
  run ro-inspect s_ro
  shutoff hx-a
  run secureboot-tpm s_sb
  run memguard s_memguard
  run proc-kill s_prockill
fi
run env-dump s_envdump
run scrub s_scrub
run cleanup cleanup
echo >> "$REPORT"; echo "failures: $FAILS" >> "$REPORT"
cat "$REPORT"
[ "$FAILS" -eq 0 ]
