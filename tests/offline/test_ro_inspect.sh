source "$(dirname "$0")/lib.sh"
mktmp
printf 'cat /etc/machine-id\n\n# comment\n  -ls /etc/netplan\nglob ls /etc/ssh/ssh_host_*\n' > "$T/cmds"
out=$("$BIN/ro-inspect" --dry-run /disk.qcow2 "$T/cmds")
assert_eq "$out" "$(printf -- '-cat /etc/machine-id\n-ls /etc/netplan\n-glob ls /etc/ssh/ssh_host_*')" "comments dropped, every command prefixed once"
"$BIN/ro-inspect" /disk.qcow2 >/dev/null 2>&1; assert_rc $? 2 "missing cmdfile -> 2"
"$BIN/ro-inspect" /disk.qcow2 "$T/nope" >/dev/null 2>&1; assert_rc $? 1 "unreadable cmdfile -> 1"
printf '# only a comment\n\n   \n' > "$T/empty"
out=$("$BIN/ro-inspect" --dry-run /disk.qcow2 "$T/empty" 2>&1); rc=$?
assert_rc $rc 1 "command file without commands -> 1"; assert_contains "$out" "no commands in $T/empty" "says why"
finish
