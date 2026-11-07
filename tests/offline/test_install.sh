source "$(dirname "$0")/lib.sh"
mktmp
export OPENCODE_SKILLS=$T/skills SKILL_BACKUPS=$T/backups
mkdir -p "$T/skills/design-doc-lab-validation"; echo old > "$T/skills/design-doc-lab-validation/SKILL.md"
"$ROOT/install.sh" --opencode >/dev/null 2>&1; rc=$?
assert_rc $rc 0 "install runs"
[ -L "$T/skills/design-doc-lab-validation" ] && ok "symlink created" || bad "symlink created"
assert_eq "$(readlink "$T/skills/design-doc-lab-validation")" "$ROOT/design-doc-lab-validation" "points to the repo"
assert_eq "$(cat "$T"/backups/design-doc-lab-validation-*/SKILL.md)" "old" "old copy backed up outside the skills dir"
assert_eq "$(ls "$T/skills")" "design-doc-lab-validation" "no second copy in the skills dir"
"$ROOT/install.sh" --opencode >/dev/null 2>&1; assert_rc $? 0 "re-run is idempotent"
"$ROOT/install.sh" --copy >/dev/null 2>&1
[ -d "$T/skills/design-doc-lab-validation" ] && [ ! -L "$T/skills/design-doc-lab-validation" ] && ok "--copy makes a real dir" || bad "--copy makes a real dir"
PYC=$ROOT/design-doc-lab-validation/scripts/kvm/__pycache__
trap 'rm -rf "$T" "$PYC"' EXIT      # the repo-tree mutation below is removed even if this test dies
mkdir -p "$PYC" && touch "$PYC/x.pyc"
"$ROOT/install.sh" --copy >/dev/null 2>&1; rm -rf "$PYC"
assert_eq "$(find "$T/skills/design-doc-lab-validation" \( -name __pycache__ -o -name .DS_Store \) | wc -l | tr -d ' ')" "0" "--copy has no __pycache__ or .DS_Store"
"$ROOT/install.sh" --zip >/dev/null 2>&1
# capture the listing first: `unzip | grep -q` under pipefail fails on SIGPIPE
zl=$(unzip -l "$ROOT/dist/design-doc-lab-validation.zip")
assert_contains "$zl" "design-doc-lab-validation/SKILL.md" "zip has SKILL.md"
assert_contains "$zl" "scripts/kvm/vm-create" "zip has scripts"
"$ROOT/install.sh" --bogus >/dev/null 2>&1; assert_rc $? 2 "usage -> 2"
finish
