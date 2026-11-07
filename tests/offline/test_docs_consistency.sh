source "$(dirname "$0")/lib.sh"
SK=$ROOT/design-doc-lab-validation
K=$SK/scripts/kvm
DOCS=("$SK/SKILL.md" "$SK"/references/*.md "$SK"/templates/*.md)

# --- SKILL.md shape
lines=$(wc -l < "$SK/SKILL.md" | tr -d ' ')
[ "$lines" -lt 500 ] && ok "SKILL.md has $lines lines (< 500)" || bad "SKILL.md has $lines lines (>= 500)"
desc=$(sed -n '/^---$/,/^---$/p' "$SK/SKILL.md" | sed -n 's/^description: //p')
case "$desc" in "Use when"*) ok "description starts with 'Use when'" ;; *) bad "description starts with 'Use when' (got '${desc:0:30}')" ;; esac
[ "${#desc}" -gt 0 ] && [ "${#desc}" -lt 1024 ] && ok "description is ${#desc} chars (< 1024)" || bad "description length ${#desc} not in 1..1023"

# --- every scripts/kvm/<name> mentioned exists
missing=""
while IFS= read -r n; do
  n=${n%.}
  [ -e "$K/$n" ] || missing="$missing $n"
done < <(grep -ohE 'scripts/kvm/[A-Za-z0-9_.-]+' "${DOCS[@]}" | sed 's:^scripts/kvm/::' | sort -u)
assert_eq "${missing# }" "" "every scripts/kvm/<name> mentioned in the docs exists"
# ... and every shipped script is named in SKILL.md
unnamed=""
for f in "$K"/*; do
  b=$(basename "$f")
  case "$b" in _lib.sh) continue ;; esac
  grep -qF "$b" "$SK/SKILL.md" || unnamed="$unnamed $b"
done
assert_eq "${unnamed# }" "" "every script in scripts/kvm is named in SKILL.md"

# --- every references/*.md and templates/*.md mentioned exists
missing=""
while IFS= read -r n; do
  [ -f "$SK/$n" ] || missing="$missing $n"
done < <(grep -ohE '(references|templates)/[A-Za-z0-9_.-]+\.md' "${DOCS[@]}" | sort -u)
assert_eq "${missing# }" "" "every references/*.md and templates/*.md mentioned exists"

# --- every P<n> cited in SKILL.md is a row of pitfalls.md; the incident count matches
missing=""
for p in $(grep -oE '\bP[0-9]+\b' "$SK/SKILL.md" | sort -u); do
  grep -qE "^\| $p \|" "$SK/references/pitfalls.md" || missing="$missing $p"
done
assert_eq "${missing# }" "" "every P<n> cited in SKILL.md has a row in pitfalls.md"
rows=$(grep -cE '^\| P[0-9]+ \|' "$SK/references/pitfalls.md")
claimed=$(grep -oE '[0-9]+ incidents' "$SK/SKILL.md" | head -1 | grep -oE '[0-9]+')
assert_eq "$claimed" "$rows" "SKILL.md incident count matches the pitfalls table"

# --- every variable named in lab.env.example is handled by _lib.sh _defaults
body=$(sed -n '/^_defaults() {/,/^}/p' "$K/_lib.sh")
missing=""
for v in $(grep -oE '^#?[A-Z][A-Z_]*=' "$K/lab.env.example" | tr -d '#=' | sort -u); do
  case "$body" in *"$v"*) ;; *) missing="$missing $v" ;; esac
done
assert_eq "${missing# }" "" "every variable in lab.env.example appears in _lib.sh _defaults"

# --- no customer names in the shipped skill, the tests (not the recorded results) or the README
names='j&j|jnj|johnson|serpro|sicredi|telecom argentina|bancolombia|vodacom|tmcel|movitel'
hits=$(grep -rilE "$names" "$SK" "$ROOT/README.md" "$ROOT/tests" --exclude-dir=results --exclude=test_docs_consistency.sh 2>/dev/null || true)
assert_eq "$hits" "" "no customer names (list)"
hits=$(grep -rilw 'chep' "$SK" "$ROOT/README.md" "$ROOT/tests" --exclude-dir=results --exclude=test_docs_consistency.sh 2>/dev/null || true)
assert_eq "$hits" "" "no customer name 'chep' (whole word)"
finish
