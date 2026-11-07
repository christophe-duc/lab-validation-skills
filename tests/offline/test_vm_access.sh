source "$(dirname "$0")/lib.sh"
mktmp
stub virsh 'exit 0'                     # domifaddr returns no address
export PATH=$T/stubs:$PATH
"$BIN/vm-ip" hx-a >/dev/null 2>&1; assert_rc $? 1 "no address -> 1"
assert_eq "$(VM_IP=10.77.0.11 "$BIN/vm-ip" hx-a)" "10.77.0.11" "VM_IP override"
"$BIN/vm-ip" >/dev/null 2>&1; assert_rc $? 2 "vm-ip usage -> 2"
out=$("$BIN/vm-ssh" hx-a true 2>&1); rc=$?
assert_rc $rc 1 "vm-ssh without address -> 1"; assert_contains "$out" "no reachable IP for hx-a" "explains"
"$BIN/vm-ssh" >/dev/null 2>&1; assert_rc $? 2 "vm-ssh usage -> 2"
"$BIN/vm-sudo" hx-a >/dev/null 2>&1; assert_rc $? 2 "vm-sudo needs two args"

# vm-sudo: password goes only via ssh stdin; command via scp'd file; sudo -n without PASSFILE
stub virsh 'case "$1" in domifaddr) echo " vnet0 52:54:00:aa:bb:cc ipv4 192.0.2.10/24";; esac; exit 0'
stub scp 'echo "$*" >> "$LOGD/scp.argv"; for a in "$@"; do [ -f "$a" ] && cat "$a" > "$LOGD/scp.content"; done; exit 0'
stub ssh 'echo "$*" >> "$LOGD/ssh.argv"; cat > "$LOGD/ssh.stdin"; exit 0'
export LOGD=$T/log; mkdir -p "$LOGD"
export VM_IP=192.0.2.10
printf 's3cretpw\n' > "$T/pw"; chmod 600 "$T/pw"
PASSFILE=$T/pw "$BIN/vm-sudo" hx-a 'id -u' >/dev/null 2>&1; assert_rc $? 0 "vm-sudo with PASSFILE succeeds"
assert_not_contains "$(cat "$LOGD/ssh.argv" "$LOGD/scp.argv")" "s3cretpw" "password not in ssh/scp argv"
assert_contains "$(cat "$LOGD/ssh.stdin")" "s3cretpw" "password fed on ssh stdin"
assert_contains "$(cat "$LOGD/scp.content")" "id -u" "scp'd temp file holds the command"
assert_contains "$(cat "$LOGD/ssh.argv")" "sudo -S" "PASSFILE -> sudo -S"
rm -f "$LOGD"/*
env -u PASSFILE "$BIN/vm-sudo" hx-a 'id -u' >/dev/null 2>&1; assert_rc $? 0 "vm-sudo without PASSFILE succeeds"
assert_contains "$(cat "$LOGD/ssh.argv")" "sudo -n" "no PASSFILE -> sudo -n"
rm -f "$LOGD"/*
out=$(PASSFILE=$T/nope "$BIN/vm-sudo" hx-a 'id -u' 2>&1); rc=$?
assert_rc $rc 1 "unreadable PASSFILE -> 1"; assert_contains "$out" "not readable" "explains unreadable PASSFILE"
if [ -e "$LOGD/scp.argv" ]; then bad "scp not called when PASSFILE unreadable"; else ok "scp not called when PASSFILE unreadable"; fi
finish
