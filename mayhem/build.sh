#!/usr/bin/env bash
#
# mayhem/build.sh — build libcoap's fuzz harnesses (tests/oss-fuzz/*_target.c, the same set OSS-Fuzz
# builds) plus the CUnit test driver. Runs in /mayhem as `mayhem`; re-runnable and offline.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

COMMON_CMAKE=(-G Ninja -DENABLE_DTLS=ON -DDTLS_BACKEND=openssl -DENABLE_DOCS=OFF -DENABLE_EXAMPLES=OFF
              -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_COMPILER="$CC")

# 1) Sanitized library (fuzzer-no-link adds SanCov so the library itself is coverage-instrumented).
LIB_CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake -S . -B build/fuzz "${COMMON_CMAKE[@]}" -DENABLE_TESTS=OFF -DCMAKE_C_FLAGS="$LIB_CFLAGS"
cmake --build build/fuzz -j"$MAYHEM_JOBS"

# 2) Harnesses: one libFuzzer binary + one run-once standalone reproducer each; leak detection off.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o build/fuzz/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/fuzz/standalone_main.o
INC=(-Ibuild/fuzz -Ibuild/fuzz/include -Iinclude -I.)
HELPER="tests/oss-fuzz/coap_fuzz_helper.c"
LIBS=(build/fuzz/libcoap-3.a -lssl -lcrypto -lpthread)
for src in tests/oss-fuzz/*_target.c; do
  name="$(basename "$src" _target.c)_fuzzer"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "${INC[@]}" $LIB_FUZZING_ENGINE \
      "$src" "$HELPER" build/fuzz/lsan_off.o "${LIBS[@]}" -o "$SRC/$name"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "${INC[@]}" \
      "$src" "$HELPER" build/fuzz/standalone_main.o build/fuzz/lsan_off.o "${LIBS[@]}" -o "$SRC/$name-standalone"
done

# 3) Unit tests with the project's NORMAL flags (no sanitizers, no coverage unless asked).
cmake -S . -B build/tests "${COMMON_CMAKE[@]}" -DENABLE_TESTS=ON -DCMAKE_C_FLAGS="$COVERAGE_FLAGS"
cmake --build build/tests -j"$MAYHEM_JOBS" --target testdriver
