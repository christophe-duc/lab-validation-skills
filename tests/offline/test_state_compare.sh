source "$(dirname "$0")/lib.sh"
mktmp
printf 'hostname=a\nmachine_id=111\nip=\n' > "$T/a.env"
printf 'hostname=b\nmachine_id=222\nip=\n' > "$T/b.env"
printf 'hostname=c\nmachine_id=111\n' > "$T/c.env"
out=$("$BIN/state-compare" --unique machine_id,hostname,ip "$T/a.env" "$T/b.env"); rc=$?
assert_rc $rc 0 "unique files pass"; assert_contains "$out" "0 duplicate(s)" "summary line"
out=$("$BIN/state-compare" --unique machine_id,ip "$T/a.env" "$T/c.env" 2>&1); rc=$?
assert_rc $rc 1 "duplicate machine_id fails"; assert_contains "$out" "DUPLICATE machine_id=111" "names key and value"
assert_contains "$out" "note: key ip absent in $T/c.env" "absent key is noted on stderr"
assert_not_contains "$out" "DUPLICATE ip" "empty values are ignored"
"$BIN/state-compare" "$T/a.env" "$T/b.env" >/dev/null 2>&1; assert_rc $? 2 "missing --unique -> 2"
"$BIN/state-compare" --unique x "$T/a.env" "$T/nope.env" >/dev/null 2>&1; assert_rc $? 2 "unreadable file -> 2"
# a unique key absent from every file is an error (typo in the key name)
out=$("$BIN/state-compare" --unique machin_id "$T/a.env" "$T/b.env" 2>&1); rc=$?
assert_rc $rc 2 "key absent in all files -> 2"
assert_contains "$out" "state-compare: key machin_id absent in all 2 files" "names the key and the count"
# absent in some files: note on stderr, not an error
printf 'machine_id=333\n' > "$T/d.env"
out=$("$BIN/state-compare" --unique hostname,machine_id "$T/a.env" "$T/d.env" 2>&1 >/dev/null); rc=$?
assert_rc $rc 0 "key absent in some files is not an error"
assert_contains "$out" "note: key hostname absent in $T/d.env" "note lists the files that lack the key"
out=$("$BIN/state-compare" --unique machine_id "$T/a.env" "$T/d.env" 2>&1 >/dev/null)
assert_not_contains "$out" "note:" "no note when every file has the key"
# binary file: no traceback
printf '\377\376\200\n\200=\377\nmachine_id=\377\376\n' > "$T/bin.env"
out=$("$BIN/state-compare" --unique machine_id "$T/a.env" "$T/bin.env" 2>&1); rc=$?
assert_not_contains "$out" "Traceback" "binary file does not raise a traceback"
assert_not_contains "$out" "DUPLICATE" "decode problems are not duplicates"
finish
