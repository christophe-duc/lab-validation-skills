source "$(dirname "$0")/lib.sh"
mktmp
cat > "$T/probe" <<EOF2
#!/usr/bin/env bash
source "$BIN/_lib.sh"
case "\${1:-}" in
  env)    load_env; echo "EVID=\$EVID IMG=\$IMG USER=\$LAB_USER MAX=\$MAX_RUNNING_GB" ;;
  opt)    load_env_optional; echo "LAB_DIR=\$LAB_DIR SECRETS=\$SECRETS" ;;
  prefix) load_env; require_prefix "\$2"; echo accepted ;;
  usage)  usage "X Y" ;;
esac
EOF2
chmod +x "$T/probe"

out=$(unset LAB_ENV LAB_DIR; "$T/probe" env 2>&1); rc=$?
assert_rc $rc 2 "load_env without lab.env exits 2"
assert_contains "$out" "no lab.env" "explains why"

mkenv 16
out=$("$T/probe" env 2>&1); rc=$?
assert_rc $rc 0 "load_env with lab.env"
assert_contains "$out" "EVID=$T/lab/evidence IMG=/var/lib/libvirt/images USER=ubuntu MAX=16" "defaults applied, file wins"
[ -d "$T/lab/evidence/timing" ] && ok "evidence dirs created" || bad "evidence dirs created"

out=$(cd "$T" && unset LAB_ENV LAB_DIR; "$T/probe" opt 2>&1); rc=$?
here=$(cd "$T" && echo "$PWD")
assert_rc $rc 0 "load_env_optional without lab.env exits 0"
assert_eq "$out" "LAB_DIR=$here SECRETS=$here/secrets" "load_env_optional defaults: LAB_DIR=\$PWD, SECRETS=\$PWD/secrets"

out=$("$T/probe" prefix hx-a 2>&1); assert_eq "$out" "accepted" "prefix accepted"
out=$("$T/probe" prefix gi-a 2>&1); rc=$?
assert_rc $rc 1 "foreign name refused"; assert_contains "$out" "VM_PREFIX" "names the prefix"

# empty VM_PREFIX: refuse to manage anything
printf 'LAB_DIR=%s\n' "$T/lab" > "$T/noprefix.env"
out=$(unset VM_PREFIX; LAB_ENV=$T/noprefix.env "$T/probe" prefix hx-a 2>&1); rc=$?
assert_rc $rc 1 "empty VM_PREFIX refused"; assert_contains "$out" "empty" "message says the prefix is empty"
# lab.env without LAB_DIR
printf 'VM_PREFIX=hx-\n' > "$T/nodir.env"
out=$(unset LAB_DIR; LAB_ENV=$T/nodir.env "$T/probe" env 2>&1); rc=$?
assert_rc $rc 2 "lab.env without LAB_DIR exits 2"; assert_contains "$out" "LAB_DIR" "message names LAB_DIR"

# MAX_RUNNING_GB default derived from host RAM (LAB_MEMINFO overrides /proc/meminfo)
printf 'LAB_DIR=%s\nVM_PREFIX=hx-\n' "$T/lab" > "$T/nomax.env"
meminfo() { printf 'MemTotal:       %s kB\nMemFree:        1 kB\n' "$(($1 * 1048576))" > "$T/meminfo"; }
maxfor() { meminfo "$1"; (unset MAX_RUNNING_GB; LAB_ENV=$T/nomax.env LAB_MEMINFO=$T/meminfo "$T/probe" env 2>&1 | sed 's/.*MAX=//'); }
assert_eq "$(maxfor 32)" "26" "32 GiB host -> 26"
assert_eq "$(maxfor 16)" "10" "16 GiB host -> 10"
assert_eq "$(maxfor 8)" "6" "8 GiB host -> 6 (minus 2)"
assert_eq "$(maxfor 4)" "4" "4 GiB host -> 4 (floor)"
assert_eq "$(maxfor 2)" "4" "2 GiB host -> 4 (floor)"
out=$(unset MAX_RUNNING_GB; LAB_ENV=$T/nomax.env LAB_MEMINFO=$T/nosuch "$T/probe" env 2>&1)
assert_contains "$out" "MAX=24" "unreadable meminfo -> 24"
meminfo 32
out=$(MAX_RUNNING_GB=7 LAB_ENV=$T/nomax.env LAB_MEMINFO=$T/meminfo "$T/probe" env 2>&1)
assert_contains "$out" "MAX=7" "environment value beats the derived default"
printf 'MAX_RUNNING_GB=9\n' >> "$T/nomax.env"
out=$(MAX_RUNNING_GB=7 LAB_ENV=$T/nomax.env LAB_MEMINFO=$T/meminfo "$T/probe" env 2>&1)
assert_contains "$out" "MAX=9" "lab.env value beats environment and derived default"

# lab.env.example must be valid shell and source cleanly
cp "$BIN/lab.env.example" "$T/example.env"
bash -n "$T/example.env"; assert_rc $? 0 "lab.env.example passes bash -n"
out=$(HOME=$T/home LAB_DIR=/tmp/x bash -c 'set -eu; . "$1"; echo "$VM_PREFIX $LAB_USER $LAB_DIR"' _ "$T/example.env" 2>&1); rc=$?
assert_rc $rc 0 "lab.env.example sources in a subshell"
assert_eq "$out" "CAMPAIGN- ubuntu $T/home/lab/CAMPAIGN" "lab.env.example sets the documented values"

out=$("$T/probe" usage 2>&1); rc=$?
assert_rc $rc 2 "usage exits 2"; assert_contains "$out" "usage: probe X Y" "usage text"
finish
