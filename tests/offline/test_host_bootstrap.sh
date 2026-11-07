source "$(dirname "$0")/lib.sh"
"$BIN/host-bootstrap" --bogus >/dev/null 2>&1; assert_rc $? 2 "usage -> 2"
bash -n "$BIN/host-bootstrap"; assert_rc $? 0 "parses"
c=$(cat "$BIN/lab.env.example")
for k in LAB_DIR VM_PREFIX LAB_USER PASSFILE SCSI_MODEL NIC_MODEL MAX_RUNNING_GB NGINX_LOG; do assert_contains "$c" "$k" "lab.env.example documents $k"; done
hb=$(cat "$BIN/host-bootstrap")
assert_not_contains "$hb" '"$USER"' "no bare \$USER (unset in non-login shells)"
assert_contains "$hb" 'USER:-$(id -un)' "falls back to id -un"
assert_contains "$hb" "grep -qx libvirt" "exact group match for libvirt"
assert_not_contains "$hb" "grep -qw libvirt" "no word-match group check"
assert_contains "$hb" "for g in libvirt kvm" "checks kvm membership too"
assert_contains "$hb" 'grep -qx "$g"' "exact group match in the per-group loop"
assert_contains "$hb" "apt-get install -y -q --no-upgrade" "installs with --no-upgrade (never upgrades installed packages)"
assert_contains "$hb" "apt-get install -s --no-upgrade" "prints the apt plan (new/upgrade) before installing"
assert_not_contains "$hb" "| grep -qx" "no early-exit grep -q in a pipe (SIGPIPE under pipefail)"
finish
