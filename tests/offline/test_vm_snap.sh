source "$(dirname "$0")/lib.sh"
mktmp; mkenv
"$BIN/vm-snap" >/dev/null 2>&1; assert_rc $? 2 "no args -> 2"
"$BIN/vm-snap" snap hx-a >/dev/null 2>&1; assert_rc $? 2 "snap needs a name"
"$BIN/vm-snap" frob hx-a x >/dev/null 2>&1; assert_rc $? 2 "unknown action -> 2"
out=$("$BIN/vm-snap" snap gi-a x 2>&1); rc=$?
assert_rc $rc 1 "foreign prefix refused"; assert_contains "$out" "VM_PREFIX" "names the prefix"
mkdir -p "$T/lab/snaps/hx-a/base1" "$T/lab/snaps/hx-a/base2"
assert_eq "$("$BIN/vm-snap" list hx-a | tr '\n' ' ')" "base1 base2 " "list"
out=$("$BIN/vm-snap" restore hx-a nope 2>&1); rc=$?
assert_rc $rc 1 "restore of missing snapshot fails"; assert_contains "$out" "no snapshot" "says why"
# restore safety. sudo is a logging stub that only runs test/cp: nothing destructive can run.
echo live > "$T/disk.qcow2"
mkdir -p "$T/lab/snaps/hx-a/s1/swtpm"; echo snapdata > "$T/lab/snaps/hx-a/s1/disk.qcow2"; echo x > "$T/lab/snaps/hx-a/s1/SHA256"
stub sudo 'echo "$*" >> "'"$T"'/sudo.log"; case "$1" in test|sha256sum) "$@";; cp) case "${@: -1}" in /var/lib/*) ;; *) "$@";; esac;; esac'
stub sha256sum 'exit 0'
stub cp 'a=(); for x in "$@"; do [ "$x" = --sparse=always ] || a+=("$x"); done; exec /bin/cp "${a[@]}"'
stub virsh 'case "$1" in
  domblklist) echo " Type Device Target Source"; echo " file disk vda '"$T"'/disk.qcow2";;
  dumpxml) echo "<domain/>";;
  domuuid) echo "${UUID-uuid-1}";;
  domstate) echo "${STATE:-running}";;
esac'
export PATH=$T/stubs:$PATH
: > "$T/sudo.log"
out=$("$BIN/vm-snap" restore hx-a s1 2>&1); rc=$?
assert_rc $rc 1 "restore refuses when VM stays running"
assert_contains "$out" "is still running; refusing to overwrite its disk" "says why"
assert_eq "$(cat "$T/disk.qcow2")" "live" "disk not overwritten"
export STATE="shut off" UUID=
out=$("$BIN/vm-snap" restore hx-a s1 2>&1); rc=$?
assert_rc $rc 1 "restore refuses with empty domuuid"; assert_contains "$out" "domuuid" "says why (uuid)"
assert_eq "$(cat "$T/disk.qcow2")" "live" "disk not overwritten (empty uuid)"
assert_not_contains "$(cat "$T/sudo.log")" "rm -rf" "no rm -rf attempted"
unset UUID
out=$("$BIN/vm-snap" restore hx-a s1 2>&1); rc=$?
assert_rc $rc 0 "shut-off VM with a uuid restores"
assert_eq "$(cat "$T/disk.qcow2")" "snapdata" "disk restored"
assert_contains "$(cat "$T/sudo.log")" "rm -rf /var/lib/libvirt/swtpm/uuid-1" "swtpm dir of this uuid replaced"
# regression (smoke run 1): virsh keeps writing rows (the seed cdrom) after awk has found the boot disk.
# An early `exit` in awk gave virsh a SIGPIPE; with pipefail + set -e vm-snap died silently, rc 1, no output.
stub virsh 'case "$1" in
  domblklist) echo " Type Device Target Source"; echo " file disk vda '"$T"'/disk.qcow2"; sleep 0.5; echo " file cdrom sda /x.iso";;
  dumpxml) sleep 0.5; echo "<domain/>"; echo "<more/>";;
  domuuid) echo uuid-1;;
  domstate) echo "shut off";;
esac'
echo live > "$T/disk.qcow2"
out=$("$BIN/vm-snap" restore hx-a s1 2>&1); rc=$?
assert_rc $rc 0 "virsh output after the boot disk row does not kill vm-snap (SIGPIPE)"
assert_eq "$(cat "$T/disk.qcow2")" "snapdata" "disk restored despite slow virsh"
finish
