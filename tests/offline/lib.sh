# lib.sh: helpers for offline tests (sourced). Every test ends with `finish`.
# shellcheck shell=bash
set -uo pipefail
# No scripts/kvm/__pycache__: importing labconsole.py writes none, and `py_compile` (which ignores
# PYTHONDONTWRITEBYTECODE) writes into a cache dir outside the repo.
export PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=${TMPDIR:-/tmp}/lab-harness-pyc
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck disable=SC2034 # lib.sh is sourced; the test files use BIN and FIX
BIN=$ROOT/design-doc-lab-validation/scripts/kvm
# shellcheck disable=SC2034 # used by the sourcing test files
FIX=$ROOT/tests/offline/fixtures
FAILS=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; FAILS=$((FAILS + 1)); }
assert_eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }
assert_rc() { if [ "$1" -eq "$2" ]; then ok "$3"; else bad "$3 (rc $1, want $2)"; fi; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }
mktmp() { T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; }
stub() { mkdir -p "$T/stubs"; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/stubs/$1"; chmod +x "$T/stubs/$1"; }
mkenv() {
  mkdir -p "$T/lab/secrets"
  printf 'LAB_DIR=%s\nVM_PREFIX=hx-\nMAX_RUNNING_GB=%s\n' "$T/lab" "${1:-24}" > "$T/lab/lab.env"
  export LAB_ENV=$T/lab/lab.env
}
finish() {
  if [ "$FAILS" -eq 0 ]; then echo "PASS $(basename "$0")"; exit 0; fi
  echo "FAIL $(basename "$0") ($FAILS)"; exit 1
}
