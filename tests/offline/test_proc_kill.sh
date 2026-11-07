source "$(dirname "$0")/lib.sh"
S=''; S2=''; trap 'kill ${S:-} ${S2:-} 2>/dev/null' EXIT
sleep 4343 >/dev/null 2>&1 & S2=$!
out=$("$BIN/proc-kill" --dry-run 'sleep 4343'); kill -0 "$S2" 2>/dev/null; assert_rc $? 0 "dry-run leaves it alive"
assert_contains "$out" "would-kill $S2" "dry-run lists it"; kill "$S2"
sleep 4242 >/dev/null 2>&1 & S=$!
# the parent bash -c command line contains the pattern: it must survive (no self-match)
out=$(bash -c "\"$BIN/proc-kill\" 'sleep 4242'; echo parent-alive")
assert_contains "$out" "parent-alive" "parent shell not killed"
assert_contains "$out" "kill $S" "target listed"
sleep 0.3; kill -0 "$S" 2>/dev/null; assert_rc $? 1 "target killed"
assert_contains "$out" "1 process(es)" "count excludes self and ancestors"
"$BIN/proc-kill" >/dev/null 2>&1; assert_rc $? 2 "no pattern -> 2"
finish
