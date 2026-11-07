source "$(dirname "$0")/lib.sh"
mktmp
stub aws 'echo "$*" >> "'"$T"'/aws.log"
case "$*" in
  *generate-cli-skeleton*) echo "{\"CpuOptions\": {\"CoreCount\": 0, \"NestedVirtualization\": \"\"}}"
    if [ -n "${STUB_SLOW:-}" ]; then sleep 0.5; echo "{\"more\": 1}"; fi ;;
  "configure get region") echo us-east-1 ;;
  *"describe-instance-types"*"--instance-types m8i"*) echo "amd-sev-snp nested-virtualization" ;;
  *"describe-instance-types"*"--instance-types"*) echo "None" ;;
  *describe-instance-types*) printf "m8i.large\tm8i.2xlarge\tc8i.large\n" ;;
  *describe-instances*) echo "m8i.2xlarge running ${STUB_NV:-enabled}" ;;
  *"ssm get-parameter"*) echo ami-0123456789abcdef0 ;;
  *"pricing get-products"*) echo "{\"terms\":{\"OnDemand\":{\"a\":{\"priceDimensions\":{\"b\":{\"pricePerUnit\":{\"USD\":\"0.1234\"}}}}}}}" ;;
  "--version") echo "aws-cli/2.99.0 Python/3" ;;
esac'
stub curl 'echo 203.0.113.7'
export PATH=$T/stubs:$PATH
out=$("$BIN/ec2-nested-check" --instance i-123); rc=$?
assert_rc $rc 0 "enabled instance passes"
assert_contains "$out" "knows CpuOptions.NestedVirtualization" "CLI flag check"
assert_contains "$out" "m8i:" "families listed"
slow=$(STUB_SLOW=1 "$BIN/ec2-nested-check")
assert_contains "$slow" "knows CpuOptions.NestedVirtualization" "aws output after the keyword does not break the CLI check (SIGPIPE)"
assert_contains "$out" "NestedVirtualization=enabled" "instance state shown"
out=$(STUB_NV=disabled "$BIN/ec2-nested-check" --instance i-123); assert_rc $? 1 "disabled instance fails"
assert_contains "$out" "NestedVirtualization=disabled" "disabled state shown (stub branch really used)"
out=$("$BIN/ec2-nested-check"); assert_contains "$out" "c8i" "control: unfiltered output lists c8i"
out=$("$BIN/ec2-nested-check" --family m8i); assert_not_contains "$out" "c8i" "--family filters"
assert_contains "$out" "m8i:" "--family keeps the requested family"
"$BIN/ec2-nested-check" --bogus >/dev/null 2>&1; assert_rc $? 2 "usage -> 2"
: > "$T/aws.log"
out=$("$BIN/ec2-launch" --name hx-smoke --type m8i.large --region us-east-1 2>&1); rc=$?
assert_rc $rc 0 "plan without --yes"
assert_contains "$out" "NestedVirtualization=enabled" "plan shows nested flag"
assert_contains "$out" "203.0.113.7/32" "SSH only from caller /32"
assert_contains "$out" "0.1234" "price shown"
assert_contains "$out" "nothing created" "says it is a dry run"
assert_contains "$out" "ami-0123456789abcdef0" "plan shows the resolved AMI id"
log=$(cat "$T/aws.log")
assert_contains "$log" "describe-instance-types" "control: aws stub was really called (log not empty)"
assert_not_contains "$log" "run-instances --region" "no launch without --yes"
assert_not_contains "$log" "create-" "nothing created without --yes"
assert_not_contains "$log" "authorize-" "no ingress rule added without --yes"
out=$("$BIN/ec2-launch" --name hx-smoke --type t3.large --region us-east-1 2>&1); rc=$?
assert_rc $rc 1 "type without nested virtualization refused"
assert_contains "$out" "does not report nested-virtualization" "refusal reason shown"
"$BIN/ec2-launch" --name x >/dev/null 2>&1; assert_rc $? 2 "missing --type -> 2"

# ---- --yes path: stubbed aws logs every call; temp HOME and cwd so nothing real is touched ----
mkdir -p "$T/stubs2"
cat > "$T/stubs2/aws" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case "$*" in
  "configure get region") echo us-east-1 ;;
  *describe-instance-types*) echo "amd-sev-snp nested-virtualization" ;;
  *"pricing get-products"*) echo "{}" ;;
  *"ssm get-parameter"*) if [ -n "${STUB_SSM_FAIL:-}" ]; then echo "An error occurred (ParameterNotFound)" >&2; exit 254; fi; if [ -n "${STUB_SSM_JUNK:-}" ]; then echo "junk-value"; exit 0; fi; if [ -n "${STUB_SSM_WARN:-}" ]; then echo "warning: deprecated" >&2; fi; echo ami-0123456789abcdef0 ;;
  *describe-key-pairs*)
    case "${STUB_KP:-missing}" in
      missing) echo "An error occurred (InvalidKeyPair.NotFound) when calling the DescribeKeyPairs operation" >&2; exit 254 ;;
      error) echo "An error occurred (UnauthorizedOperation) when calling the DescribeKeyPairs operation" >&2; exit 254 ;;
      exists) echo '{}' ;;
    esac ;;
  *create-key-pair*) if [ -n "${STUB_CKP_FAIL:-}" ]; then echo "An error occurred (LimitExceeded)" >&2; exit 254; fi; echo "-----BEGIN FAKE KEY-----" ;;
  *describe-security-groups*) echo None ;;
  *create-security-group*) echo sg-0123 ;;
  *authorize-security-group-ingress*)
    case "${STUB_AUTH:-ok}" in
      ok) echo '{}' ;;
      dup) echo "An error occurred (InvalidPermission.Duplicate) when calling the Authorize operation" >&2; exit 254 ;;
      err) echo "An error occurred (UnauthorizedOperation) when calling the Authorize operation" >&2; exit 254 ;;
    esac ;;
  *"describe-instances"*"tag:Name"*)
    if [ -n "${STUB_LIVE_FAIL:-}" ]; then echo "An error occurred (RequestLimitExceeded) when calling DescribeInstances" >&2; exit 254; fi
    if [ -n "${STUB_LIVE_WARN:-}" ]; then echo "warning: something" >&2; fi
    if [ -n "${STUB_EXISTING:-}" ]; then echo i-old; fi ;;
  *"describe-instances"*"--instance-ids"*)
    if [ -n "${STUB_IP_FAIL:-}" ]; then echo "An error occurred (Throttling)" >&2; exit 254; fi
    if [ -n "${STUB_NOIP:-}" ]; then echo None; else echo 198.51.100.9; fi ;;
  *run-instances*) echo i-0new ;;
  *"wait instance-running"*) if [ -n "${STUB_WAIT_FAIL:-}" ]; then echo "Waiter failed" >&2; exit 255; fi ;;
esac
STUB
cat > "$T/stubs2/curl" <<'STUB'
#!/usr/bin/env bash
if [ -n "${STUB_CURL_FAIL:-}" ]; then exit 6; fi
echo "${STUB_CURL_BODY:-203.0.113.7}"
STUB
chmod +x "$T/stubs2/aws" "$T/stubs2/curl"
export STUB_LOG=$T/yes.log
N=0
# world: fresh HOME (no ~/.ssh unless asked) and cwd; sets H, W
world() { N=$((N + 1)); H=$T/w$N/home; W=$T/w$N/cwd; mkdir -p "$H" "$W"; : > "$STUB_LOG"; }
launch() { (cd "$W" && HOME=$H PATH=$T/stubs2:$PATH "$BIN/ec2-launch" --region us-east-1 "$@" 2>&1); }

world
out=$(launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 0 "--yes launch succeeds"
ylog=$(cat "$STUB_LOG")
assert_contains "$ylog" "create-key-pair" "creates the key pair"
assert_contains "$ylog" "create-security-group" "creates the security group"
assert_contains "$ylog" "authorize-security-group-ingress" "adds the ingress rule"
assert_contains "$ylog" "run-instances" "launches the instance"
assert_contains "$ylog" "--cpu-options NestedVirtualization=enabled" "run-instances has nested virtualization"
for bad_op in terminate-instances stop-instances delete- modify-; do
  assert_not_contains "$ylog" "$bad_op" "no $bad_op call"
done
envf=$(cat "$W/instance-hx-yes.env")
assert_contains "$envf" "INSTANCE_ID=i-0new" "env file has INSTANCE_ID"
assert_contains "$envf" "PUBLIC_IP=198.51.100.9" "env file has PUBLIC_IP"
perm=$(ls -l "$H/.ssh/hx-yes.pem" | cut -c1-10)
assert_eq "$perm" "-rw-------" "pem has mode 600"
# shellcheck disable=SC2088 # the tilde is in a message string, not a path
assert_eq "$(stat_perm=$(ls -ld "$H/.ssh" | cut -c1-10); echo "$stat_perm")" "drwx------" "~/.ssh created with mode 700"
assert_eq "$(ls -A "$H/.ssh")" "hx-yes.pem" "no temp key file left behind"

world; : > "$W/instance-hx-yes.env"
out=$(launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "re-run refused when env file exists"
assert_contains "$out" "instance-hx-yes.env" "refusal names the env file"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch when env file exists"

world
out=$(STUB_EXISTING=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "refused when a live instance carries the Name tag"
assert_contains "$out" "i-old" "refusal shows the existing instance id"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch when tagged instance exists"
assert_contains "$(cat "$STUB_LOG")" "Name=tag:Name,Values=hx-yes" "control: guard queried by tag:Name"
assert_contains "$(cat "$STUB_LOG")" "instance-state-name,Values=pending,running,stopping,stopped" "guard state filter pinned"

world; mkdir -p "$H/.ssh"; echo KEEP > "$H/.ssh/hx-yes.pem"
out=$(STUB_KP=error launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "non-NotFound describe-key-pairs error aborts"
assert_contains "$out" "UnauthorizedOperation" "AWS message shown"
assert_eq "$(cat "$H/.ssh/hx-yes.pem")" "KEEP" "existing pem untouched on describe error"
assert_not_contains "$(cat "$STUB_LOG")" "create-key-pair" "no key creation on describe error"

world; mkdir -p "$H/.ssh"; echo KEEP > "$H/.ssh/hx-yes.pem"
out=$(launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "existing local pem + key missing in AWS refuses"
assert_eq "$(cat "$H/.ssh/hx-yes.pem")" "KEEP" "existing pem not overwritten"
assert_not_contains "$(cat "$STUB_LOG")" "create-key-pair" "no create-key-pair when a local pem exists"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch when a local pem exists"

world; mkdir -p "$H/.ssh"
out=$(STUB_CKP_FAIL=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "failed create-key-pair aborts"
assert_eq "$(ls -A "$H/.ssh")" "" "failed create leaves no pem or temp file"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch after failed key creation"

world; mkdir -p "$H/.ssh"; echo KEEP > "$H/.ssh/hx-yes.pem"
out=$(STUB_KP=exists launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 0 "existing AWS key + local pem is reused"
assert_eq "$(cat "$H/.ssh/hx-yes.pem")" "KEEP" "reused pem untouched"
assert_not_contains "$(cat "$STUB_LOG")" "create-key-pair" "reuse does not create a key"

world
out=$(STUB_CURL_BODY='<html>' launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "invalid public IP body exits 1"
assert_contains "$out" "ec2-launch:" "invalid IP message"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch on invalid IP"
world
out=$(STUB_CURL_FAIL=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "curl failure exits 1"
assert_contains "$out" "ec2-launch: could not determine your public IP (checkip.amazonaws.com)" "curl failure message"

world
out=$(STUB_AUTH=err launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "ingress error other than Duplicate aborts"
assert_contains "$out" "UnauthorizedOperation" "ingress AWS message shown"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch after ingress error"
world
out=$(STUB_AUTH=dup launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 0 "Duplicate ingress tolerated"
assert_contains "$(cat "$STUB_LOG")" "run-instances" "launch proceeds after Duplicate"

world
out=$(STUB_WAIT_FAIL=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "failed wait exits 1"
assert_contains "$out" "i-0new" "failed wait prints the instance id"
assert_contains "$out" "ec2-nested-check" "failed wait prints the check command"
envf=$(cat "$W/instance-hx-yes.env")
assert_contains "$envf" "INSTANCE_ID=i-0new" "env file already holds the id after failed wait"

# id must never be lost: unwritable cwd -> id on stderr, exit 1
world; chmod 555 "$W"
if [ "$(id -u)" = 0 ] || (: > "$W/.probe") 2>/dev/null; then
  echo "note: cwd stays writable (root?); skipping read-only-cwd assertions"; rm -f "$W/.probe"
else
  out=$(launch --name hx-yes --type m8i.large --yes); rc=$?
  assert_rc $rc 1 "unwritable cwd exits 1"
  assert_contains "$out" "launched i-0new" "id printed before write_env"
  assert_contains "$out" "could not write ./instance-hx-yes.env" "write failure explained"
  assert_contains "$out" "i-0new" "id present in the failure message"
fi
chmod 755 "$W"
world
out=$(STUB_IP_FAIL=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "failed public-IP lookup exits 1"
assert_contains "$out" "i-0new" "IP lookup failure prints the id"
assert_contains "$out" "ec2-nested-check" "IP lookup failure prints the check command"
assert_contains "$(cat "$W/instance-hx-yes.env")" "INSTANCE_ID=i-0new" "env file holds the id after IP failure"
world
out=$(STUB_NOIP=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 0 "no public address is not fatal"
envf=$(cat "$W/instance-hx-yes.env")
assert_not_contains "$envf" "None" "env file never contains None"
assert_contains "$envf" "PUBLIC_IP=
" "PUBLIC_IP is empty"
assert_contains "$out" "no public IP" "note printed for missing public address"
# stderr noise must not corrupt parsed values
world
out=$(STUB_SSM_WARN=1 STUB_LIVE_WARN=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 0 "stderr warnings do not break AMI/LIVE parsing"
assert_contains "$(cat "$STUB_LOG")" "--image-id ami-0123456789abcdef0 " "AMI id clean despite stderr warning"
# junk AMI value / describe-instances failure: stop before any create call
world
out=$(STUB_SSM_JUNK=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "junk AMI value exits 1"
assert_not_contains "$(cat "$STUB_LOG")" "create-" "no create call after junk AMI"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch after junk AMI"
world
out=$(STUB_LIVE_FAIL=1 launch --name hx-yes --type m8i.large --yes); rc=$?
assert_rc $rc 1 "failing describe-instances exits 1"
assert_contains "$out" "RequestLimitExceeded" "describe-instances message shown"
assert_not_contains "$(cat "$STUB_LOG")" "run-instances" "no launch when the live check fails"
assert_not_contains "$(cat "$STUB_LOG")" "create-" "no create call when the live check fails"

world
out=$(launch --name hx-yes --type m8i.large 2>&1)
assert_not_contains "$(cat "$STUB_LOG")" "create-key-pair" "control: dry run via launch() creates nothing"

world
out=$(STUB_SSM_FAIL=1 launch --name hx-yes --type m8i.large); rc=$?
assert_rc $rc 1 "AMI lookup failure in the plan exits 1"
assert_contains "$out" "ParameterNotFound" "AMI failure message shown"
out=$(launch --name hx-yes --type m8i.large)
assert_contains "$out" "ami-0123456789abcdef0" "plan prints the AMI id"

world
launch --name 'bad name' --type m8i.large >/dev/null; assert_rc $? 2 "invalid NAME -> 2"
launch --name 'a/b' --type m8i.large >/dev/null; assert_rc $? 2 "NAME with slash -> 2"
launch --name ok --key '../x' --type m8i.large >/dev/null; assert_rc $? 2 "invalid KEY -> 2"
launch --name ok --disk-gb 20x --type m8i.large >/dev/null; assert_rc $? 2 "invalid DISK -> 2"
: > "$STUB_LOG"
out=$(launch --name 'bad name' --type m8i.large); assert_contains "$out" "usage:" "usage text shown"
assert_eq "$(cat "$STUB_LOG")" "" "validation happens before any aws call"
# PATH with only bash in it: no aws can be found, whatever the machine has installed
mkdir -p "$T/nobin"; ln -s "$(command -v bash)" "$T/nobin/bash"
out=$(cd "$W" && HOME=$H PATH=$T/nobin "$BIN/ec2-launch" --name ok --type m8i.large 2>&1); rc=$?
assert_rc $rc 1 "missing aws CLI -> 1"
assert_contains "$out" "aws CLI not found" "missing aws message"
finish
