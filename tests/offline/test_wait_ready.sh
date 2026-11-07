source "$(dirname "$0")/lib.sh"
mktmp; mkenv
stub virsh 'case "$1" in domstats) printf "Domain: x\n  cpu.time=123\n  block.0.wr.bytes=456\n";; esac; exit 0'
export PATH=$T/stubs:$PATH
out=$("$BIN/wait-ready" hx-a 1 2>&1); rc=$?
assert_rc $rc 1 "times out"
assert_contains "$out" "TIMEOUT waiting for SSH on hx-a" "timeout message"
assert_contains "$out" "cpu.time=123" "heartbeat shows VM CPU time"
assert_contains "$out" "block.0.wr.bytes=456" "heartbeat shows disk writes"
"$BIN/wait-ready" hx-a abc >/dev/null 2>&1; assert_rc $? 2 "non-numeric TIMEOUT_S -> 2"
"$BIN/wait-ready" >/dev/null 2>&1; assert_rc $? 2 "usage -> 2"
finish
