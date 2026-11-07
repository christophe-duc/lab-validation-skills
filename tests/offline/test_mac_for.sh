source "$(dirname "$0")/lib.sh"
assert_eq "$("$BIN/mac-for" gi-build)" "52:54:00:a6:99:99" "matches the MAC used in the golden-image lab"
assert_eq "$("$BIN/mac-for" gi-c1)" "52:54:00:64:aa:70" "second known value"
assert_eq "$("$BIN/mac-for" hx-a)" "$("$BIN/mac-for" hx-a)" "deterministic"
"$BIN/mac-for" >/dev/null 2>&1; assert_rc $? 2 "no argument -> 2"
finish
