#!/usr/bin/env bash
# run.sh: run every offline test; exit 1 if any fails.
# No `set -euo pipefail` on purpose: a failing test must not stop the loop; failures accumulate in $rc.
cd "$(dirname "$0")" || exit 2
rc=0
for t in test_*.sh; do bash "$t" || rc=1; done
exit $rc
