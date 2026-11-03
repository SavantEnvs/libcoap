#!/usr/bin/env bash
#
# mayhem/test.sh — RUN libcoap's CUnit suite (tests/testdriver.c, built by mayhem/build.sh with the
# project's normal flags). CUnit's asserts check decoded/encoded values, so a neutered library fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER=build/tests/testdriver
[ -x "$RUNNER" ] || { echo "test.sh: $RUNNER missing — mayhem/build.sh should have built it" >&2; exit 2; }

out="$("$RUNNER" 2>&1)"; rc=$?
printf '%s\n' "$out" | tail -n 20

# CUnit summary row:  "               tests     57     57     57      0        0"  (Total Ran Passed Failed Inactive)
read -r total ran passed failed inactive < <(printf '%s\n' "$out" | awk '$1=="tests" && NF==6 {print $2,$3,$4,$5,$6; exit}')
if [ -z "${total:-}" ] || [ "${ran:-0}" -eq 0 ]; then
  echo "test.sh: no CUnit 'tests' summary row (or zero tests ran) — treating as failure" >&2
  emit_ctrf cunit 0 1 0
  exit 1
fi
[ "$rc" -eq 0 ] || failed=$(( failed > 0 ? failed : 1 ))
emit_ctrf cunit "$passed" "$failed" "$inactive"
