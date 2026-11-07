source "$(dirname "$0")/lib.sh"
mktmp; mkenv 10
stub virsh 'case "$1" in list) echo hx-run;; dominfo) [ -n "${STUB_DOMINFO_FAIL:-}" ] && exit 1; echo "Max memory:     4194304 KiB";; esac'
stub virt-install 'printf "%s\n" "$@" > "'"$T"'/vi.args"'
export PATH=$T/stubs:$PATH
"$BIN/vm-create" >/dev/null 2>&1; assert_rc $? 2 "no args -> 2"
"$BIN/vm-create" hx-a --disk /x >/dev/null 2>&1; assert_rc $? 2 "disk without --import or --kernel -> 2"
"$BIN/vm-create" hx-a --disk /x --size 3 --import >/dev/null 2>&1; assert_rc $? 2 "disk and size -> 2"
out=$("$BIN/vm-create" gi-a --disk /x --import 2>&1); rc=$?
assert_rc $rc 1 "foreign prefix refused"; assert_contains "$out" "VM_PREFIX" "names the prefix"
out=$(MEM=8192 "$BIN/vm-create" hx-a --disk /x --import 2>&1); rc=$?     # 4 GiB running + 8 > 10
assert_rc $rc 1 "memory guard refuses"; assert_contains "$out" "memory guard" "says why"
[ -f "$T/vi.args" ] && bad "virt-install must not run" || ok "virt-install not called"
out=$(STUB_DOMINFO_FAIL=1 MEM=8192 "$BIN/vm-create" hx-a --disk /x --import 2>&1); rc=$?
assert_rc $rc 0 "dominfo failure: keeps going"
assert_contains "$out" "warning: cannot read memory of hx-run, counted as 0" "dominfo failure: warns on stderr"
out=$(MEM=2048 "$BIN/vm-create" hx-a --disk /img/hx-a.qcow2 --import --cdrom /img/seed.iso 2>&1); rc=$?
assert_rc $rc 0 "within limit starts"
args=$(cat "$T/vi.args")
assert_contains "$args" "loader=/usr/share/OVMF/OVMF_CODE_4M.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS_4M.fd" "explicit OVMF loader"
assert_contains "$args" "$(printf -- '--tpm\nnone')" "TPM off by default (--tpm none)"
assert_not_contains "$args" "tpm-crb" "no TPM device by default"
assert_contains "$args" "network=default,model=virtio,mac=$("$BIN/mac-for" hx-a)" "stable MAC"
assert_contains "$args" "path=/img/seed.iso,device=cdrom,bus=sata,readonly=on" "cdrom attached"
assert_contains "$args" "--import" "import mode"
out=$(MEM=1024 SB=yes TPM=yes "$BIN/vm-create" hx-b --disk /x --import 2>&1)
args=$(cat "$T/vi.args")
assert_contains "$args" "firmware.feature0.name=secure-boot" "Secure Boot variant"
assert_contains "$args" "smm.state=on" "SMM for Secure Boot"
assert_contains "$args" "emulator,model=tpm-crb,version=2.0" "swtpm"
assert_not_contains "$args" "$(printf -- '--tpm\nnone')" "TPM=yes drops --tpm none"
[ -f "$T/lab/evidence/timing/hx-a.started" ] && ok "start time recorded" || bad "start time recorded"
stub sudo '"$@"'                                   # run qemu-img/test/rm without sudo
stub qemu-img 'echo "qemu-img $*" >> "'"$T"'/qi.log"; touch "${@: -1}"'
export IMG=$T/img; mkdir -p "$IMG"; printf 'IMG=%s\n' "$IMG" >> "$LAB_ENV"
"$BIN/vm-clone" hx-c relative.qcow2 >/dev/null 2>&1; assert_rc $? 1 "relative base refused"
out=$(MEM=8192 "$BIN/vm-clone" hx-c /base.qcow2 2>&1); rc=$?
assert_rc $rc 1 "memory guard propagates"; [ -e "$IMG/hx-c.qcow2" ] && bad "overlay removed on failure" || ok "overlay removed on failure"
out=$(MEM=1024 "$BIN/vm-clone" hx-c /base.qcow2 /seed.iso 2>&1); rc=$?
assert_rc $rc 0 "clone starts"
assert_contains "$(cat "$T/qi.log")" "create -q -f qcow2 -F qcow2 -b /base.qcow2 $IMG/hx-c.qcow2" "overlay on base"
assert_contains "$(cat "$T/vi.args")" "path=$IMG/hx-c.qcow2,bus=scsi" "boots the overlay"
"$BIN/vm-clone" hx-c /base.qcow2 >/dev/null 2>&1; assert_rc $? 1 "existing overlay refused"
rm -f "$T/vi.args"; touch "$IMG/hx-p-pvdata.qcow2"
out=$(PVDATA=yes MEM=1024 "$BIN/vm-create" hx-p --disk /x --import 2>&1); rc=$?
assert_rc $rc 1 "existing pvdata disk refused"; assert_contains "$out" "hx-p-pvdata.qcow2 already exists" "names the pvdata disk"
[ -f "$T/vi.args" ] && bad "virt-install must not run" || ok "virt-install not called (pvdata)"
printf '#!/usr/bin/env bash\nexit 3\n' > "$T/hook"; chmod +x "$T/hook"
out=$(PRE_HOOK=$T/hook MEM=1024 "$BIN/vm-clone" hx-h /base.qcow2 2>&1); rc=$?
assert_rc $rc 3 "failed PRE_HOOK exit status propagates"
[ -e "$IMG/hx-h.qcow2" ] && bad "overlay removed when PRE_HOOK fails" || ok "overlay removed when PRE_HOOK fails"
[ -f "$T/vi.args" ] && bad "virt-install must not run after hook failure" || ok "virt-install not called after hook failure"
finish
