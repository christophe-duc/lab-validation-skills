source "$(dirname "$0")/lib.sh"
mktmp
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT   # a failed chmod 000 case must not leave an undeletable dir
mkdir -p "$T/sec/keys" "$T/ev/logs"
printf 'TOKENabcdef123456\n\nab\n        \n' > "$T/sec/pro-token"   # blank, short and whitespace-only lines must not match everything
printf 'DOTFILEsecret99887\n' > "$T/sec/.token"                       # dotfile in the secrets dir
printf 'NESTEDsecret55443322\n' > "$T/sec/keys/x"                      # file in a subdirectory
echo "dot=DOTFILEsecret99887" > "$T/ev/logs/dot.txt"
echo "nested=NESTEDsecret55443322" > "$T/ev/logs/nested.txt"
echo "plain text with spaces   and more" > "$T/ev/logs/spaces.txt"      # must not hit via the whitespace-only line
echo "ssh-ed25519 AAAAC3NzaFAKEKEYFAKEKEY test@x" > "$T/key.pub"
echo "token=TOKENabcdef123456" > "$T/ev/logs/a.txt"
H1='$6$'; H2='testsalt12345678$FAKEHASHFAKEHASHFAKEHASH'   # built in two parts so this file does not itself match the hash scan
echo "<td>labadmin:${H1}${H2}:19000</td>" > "$T/ev/b.html"
echo 'hash prefix $6$ is expected' > "$T/ev/c.txt"
K='PRIVATE'; echo "-----BEGIN OPENSSH ${K} KEY-----" > "$T/ev/d.key"   # split marker, same reason
echo 'authorized: AAAAC3NzaFAKEKEYFAKEKEY' > "$T/ev/e.txt"
out=$("$BIN/scrub-evidence" --secrets "$T/sec" --pubkey "$T/key.pub" "$T/ev" 2>&1); rc=$?
assert_rc $rc 1 "hits found"
assert_contains "$out" "HIT secret $T/ev/logs/a.txt" "secret file content"
assert_contains "$out" "HIT hash $T/ev/b.html" "password hash"
assert_contains "$out" "HIT private-key $T/ev/d.key" "private key"
assert_contains "$out" "HIT secret $T/ev/e.txt" "public key"
assert_contains "$out" "HIT secret $T/ev/logs/dot.txt" "secret from a dotfile in the secrets dir"
assert_contains "$out" "HIT secret $T/ev/logs/nested.txt" "secret from a file in a secrets subdir"
assert_not_contains "$out" "spaces.txt" "short and whitespace-only secret lines are skipped"
assert_not_contains "$out" "c.txt" "bare \$6\$ prefix is not a hash"
assert_not_contains "$out" "TOKENabcdef123456" "never prints a secret value"
"$BIN/scrub-evidence" --fix --secrets "$T/sec" "$T/ev" >/dev/null 2>&1
assert_contains "$(cat "$T/ev/b.html")" "labadmin:<scrubbed-hash>:19000" "--fix redacts the hash"
rm "$T/ev/logs/a.txt" "$T/ev/d.key" "$T/ev/e.txt" "$T/ev/logs/dot.txt" "$T/ev/logs/nested.txt"
out=$("$BIN/scrub-evidence" --secrets "$T/sec" "$T/ev" 2>&1); rc=$?
assert_rc $rc 0 "clean bundle passes"; assert_contains "$out" "scrub-evidence: $T/ev is clean" "says clean"
assert_not_contains "$out" "secrets not checked" "secrets were checked: plain clean"
# no secrets dir at all (the note path): still exit 0, but the line says secrets were not checked
out=$(cd "$T" && unset LAB_ENV LAB_DIR && "$BIN/scrub-evidence" "$T/ev" 2>&1); rc=$?
assert_rc $rc 0 "no secrets dir: exit 0"
assert_contains "$out" "note: no secrets dir at" "no secrets dir: note"
assert_contains "$out" "scrub-evidence: $T/ev is clean of hashes and private keys (secrets not checked)" "no secrets dir: clean line says secrets not checked"
# lab.env with a secrets dir: plain clean
mkenv 8; cp "$T/sec/pro-token" "$T/lab/secrets/"
out=$("$BIN/scrub-evidence" "$T/ev" 2>&1); rc=$?
assert_rc $rc 0 "secrets dir from lab.env: exit 0"
assert_contains "$out" "scrub-evidence: $T/ev is clean" "secrets dir from lab.env: clean"
assert_not_contains "$out" "secrets not checked" "secrets dir from lab.env: plain clean"
unset LAB_ENV
"$BIN/scrub-evidence" >/dev/null 2>&1; assert_rc $? 2 "no dir -> 2"
# explicit --secrets dir that does not exist must fail closed
out=$("$BIN/scrub-evidence" --secrets "$T/nosuch" "$T/ev" 2>&1); rc=$?
assert_rc $rc 2 "missing explicit --secrets dir -> 2"
assert_contains "$out" "scrub-evidence: secrets dir $T/nosuch not found" "missing secrets dir message"
assert_not_contains "$out" "clean" "missing secrets dir never clean"
# symlinked secrets dir: find must follow it (secret planted in the evidence must be found)
mkdir -p "$T/ev2/logs"; echo "token=TOKENabcdef123456" > "$T/ev2/logs/s.txt"
ln -s "$T/sec" "$T/seclink"
out=$("$BIN/scrub-evidence" --secrets "$T/seclink" "$T/ev2" 2>&1); rc=$?
assert_rc $rc 1 "symlinked secrets dir: hit -> 1"
assert_contains "$out" "HIT secret $T/ev2/logs/s.txt" "symlinked secrets dir is followed"
assert_not_contains "$out" "is clean" "symlinked secrets dir never clean"
# symlinked file inside the secrets dir
mkdir -p "$T/sec3" "$T/real"; printf 'LINKEDsecret778899\n' > "$T/real/v"; ln -s "$T/real/v" "$T/sec3/v"
echo "x=LINKEDsecret778899" > "$T/ev2/logs/l.txt"
out=$("$BIN/scrub-evidence" --secrets "$T/sec3" "$T/ev2" 2>&1); rc=$?
assert_rc $rc 1 "symlinked secrets file: hit -> 1"
assert_contains "$out" "HIT secret $T/ev2/logs/l.txt" "symlinked file in secrets dir is read"
# empty secrets dir (as created at Phase 4): nothing was checked, say so
mkdir -p "$T/sec0" "$T/ev0"; echo "plain" > "$T/ev0/p.txt"
out=$("$BIN/scrub-evidence" --secrets "$T/sec0" "$T/ev0" 2>&1); rc=$?
assert_rc $rc 0 "empty secrets dir: exit 0"
assert_contains "$out" "scrub-evidence: $T/ev0 is clean of hashes and private keys (secrets not checked)" "empty secrets dir: secrets not checked"
# secrets dir holding only blank/short lines is also not a check
printf 'ab\n\n   \n' > "$T/sec0/short"
out=$("$BIN/scrub-evidence" --secrets "$T/sec0" "$T/ev0" 2>&1)
assert_contains "$out" "(secrets not checked)" "only blank/short lines: secrets not checked"
# unreadable subdirectory: scan cannot complete -> never clean (root ignores modes: skip)
if [ "$(id -u)" = 0 ]; then
  echo "note: running as root, chmod 000 has no effect; skipping the unreadable-dir cases"
else
  mkdir -p "$T/ev/locked"; echo x > "$T/ev/locked/f.txt"; chmod 000 "$T/ev/locked"
  out=$("$BIN/scrub-evidence" --secrets "$T/sec" "$T/ev" 2>&1); rc=$?
  chmod 755 "$T/ev/locked"
  assert_rc $rc 1 "unreadable subdir -> 1"
  assert_contains "$out" "scrub-evidence: grep failed on $T/ev (unreadable files?)" "grep-failed message"
  assert_not_contains "$out" "is clean" "unreadable subdir never clean"
  rm -rf "$T/ev/locked"
  # unreadable secrets file: the scan is incomplete -> never clean
  mkdir -p "$T/sec2"; echo 'LOCKEDsecret1234' > "$T/sec2/f"; chmod 000 "$T/sec2/f"
  out=$("$BIN/scrub-evidence" --secrets "$T/sec2" "$T/ev" 2>&1); rc=$?
  chmod 644 "$T/sec2/f"
  assert_rc $rc 1 "unreadable secrets file -> 1"; assert_not_contains "$out" "is clean" "unreadable secrets file never clean"
  # unreadable subdirectory inside the secrets dir: listing is incomplete -> never clean
  mkdir -p "$T/sec4/locked"; echo 'HIDDENsecret123456' > "$T/sec4/locked/f"; chmod 000 "$T/sec4/locked"
  out=$("$BIN/scrub-evidence" --secrets "$T/sec4" "$T/ev0" 2>&1); rc=$?
  chmod 755 "$T/sec4/locked"
  assert_rc $rc 1 "unreadable secrets subdir -> 1"
  assert_not_contains "$out" "is clean" "unreadable secrets subdir never clean"
  assert_contains "$out" "scrub-evidence: find failed on $T/sec4" "find-failed message"
  assert_contains "$out" "scrub-evidence: scan incomplete: the secrets directory could not be read completely" "find failure: secrets-dir message"
  assert_not_contains "$out" "grep failed" "find failure: no misleading grep-failed line"
  assert_contains "$(chmod 000 "$T/sec2/f"; "$BIN/scrub-evidence" --secrets "$T/sec2" "$T/ev0" 2>&1; chmod 644 "$T/sec2/f")" "the secrets directory could not be read completely" "unreadable secrets file: secrets-dir message"
fi
# dangling symlink in the secrets dir: find -L lists it as type l; awk must fail on it -> incomplete, never clean
mkdir -p "$T/sec5" "$T/ev5"; echo plain > "$T/ev5/p.txt"
printf 'REALsecret998877\n' > "$T/sec5/real"; ln -s "$T/nonexistent-target" "$T/sec5/dangling"
out=$("$BIN/scrub-evidence" --secrets "$T/sec5" "$T/ev5" 2>&1); rc=$?
assert_rc $rc 1 "real file + dangling symlink in secrets dir -> 1"
assert_not_contains "$out" "is clean" "dangling symlink: never clean"
assert_contains "$out" "the secrets directory could not be read completely" "dangling symlink: incomplete message"
assert_not_contains "$out" "grep failed" "dangling symlink: no grep-failed line"
mkdir -p "$T/sec6"; ln -s "$T/nonexistent-target" "$T/sec6/dangling"
out=$("$BIN/scrub-evidence" --secrets "$T/sec6" "$T/ev5" 2>&1); rc=$?
assert_rc $rc 1 "only a dangling symlink in secrets dir -> 1"
assert_not_contains "$out" "is clean" "only dangling symlink: never clean"
# secrets dir path starting with '-': must not be taken as a find option
mkdir -p "$T/dash"; ( cd "$T/dash" && mkdir -- -sec && printf 'DASHsecret445566\n' > ./-sec/v && mkdir ev && echo "x=DASHsecret445566" > ev/f.txt )
out=$(cd "$T/dash" && "$BIN/scrub-evidence" --secrets -sec ev 2>&1); rc=$?
assert_rc $rc 1 "secrets dir starting with '-': hit -> 1"
assert_contains "$out" "HIT secret ev/f.txt" "secrets dir starting with '-' is read"
assert_not_contains "$out" "find failed" "secrets dir starting with '-': no find error"
# known limit: symlinks inside the evidence dir are not followed (grep -R is not portable to macOS BSD grep);
# the limit must stay documented in the script header and in references/recipes.md
mkdir -p "$T/ev7" "$T/outside"; echo "leak=TOKENabcdef123456" > "$T/outside/leak.txt"; ln -s "$T/outside/leak.txt" "$T/ev7/leaklink.txt"
out=$("$BIN/scrub-evidence" --secrets "$T/sec" "$T/ev7" 2>&1); rc=$?
assert_rc $rc 0 "symlink in evidence dir is not followed (documented limit)"
assert_contains "$(cat "$BIN/scrub-evidence")" "symlinks inside the evidence dir are not followed" "limit documented in script header"
assert_contains "$(cat "$BIN/../../references/recipes.md")" "symlinks inside the evidence dir are not followed" "limit documented in recipes.md"
finish
