#!/usr/bin/env bash
# lint.sh: shellcheck every bash script of the harness, py_compile the Python ones. Exit 1 on any finding.
# No `set -euo pipefail` on purpose: every file is checked and failures accumulate in $rc.
cd "$(dirname "$0")/.." || exit 2
B=design-doc-lab-validation/scripts/kvm; rc=0
PYC=$(mktemp -d); export PYTHONPYCACHEPREFIX="$PYC"   # keep __pycache__ out of scripts/kvm
for f in "$B"/* install.sh tests/*.sh tests/offline/*.sh; do
  [ -f "$f" ] || continue
  case "$f" in *.example) continue ;; esac
  if head -1 "$f" | grep -q python3; then python3 -m py_compile "$f" || rc=1; continue; fi
  case "$f" in
    tests/*) shellcheck -s bash -S warning -e SC2015 "$f" || rc=1 ;;   # tests: no shebang; assertion idiom `[ ] && ok || bad`
    *)       shellcheck -x -P "$B" "$f" || rc=1 ;;              # harness: every finding counts
  esac
done
rm -rf "$PYC"
[ $rc -eq 0 ] && echo "lint: clean"
exit $rc
