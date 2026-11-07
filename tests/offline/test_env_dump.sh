source "$(dirname "$0")/lib.sh"
mktmp; mkenv
stub curl 'exit 7'               # no IMDS
stub virsh 'echo " Id   Name   State"'
stub sudo '"$@"'
export PATH=$T/stubs:$PATH
echo hello > "$T/art.bin"
out=$("$BIN/env-dump" "$T/art.bin"); f=${out#wrote }
assert_eq "$f" "$T/lab/evidence/environment.txt" "first dump name"
c=$(cat "$f")
for s in "## os" "## tools" "## ec2" "not on EC2" "## vms" "## artifacts"; do assert_contains "$c" "$s" "section $s"; done
assert_contains "$c" "$T/art.bin" "artifact hashed"
out=$("$BIN/env-dump"); assert_contains "$out" "environment-" "second dump does not overwrite"
stub sudo 'if [ "$1" = test ]; then shift; test "$@"; else "$@"; fi'
sleep 1                        # timestamped names have 1 s resolution
n=$(ls "$T/lab/evidence" | wc -l)
out=$("$BIN/env-dump" "$T/art.bin" "$T/missing.bin" 2>&1); rc=$?
assert_rc $rc 1 "unreadable artifact -> 1"; assert_contains "$out" "cannot read artifact $T/missing.bin" "names the artifact"
assert_eq "$(ls "$T/lab/evidence" | wc -l | tr -d ' ')" "$(echo "$n" | tr -d ' ')" "no output file written on failure"
finish
