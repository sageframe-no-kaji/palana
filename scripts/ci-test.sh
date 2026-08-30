#!/usr/bin/env bash
# Runs the suite under a watchdog.
#
# A hang used to eat the runner's entire 30-minute budget and report
# nothing useful: the job was killed from outside, so no stack, no name,
# no evidence — three weeks of red main with no way in. This bounds the
# run and, on timeout, SAMPLES the stuck processes before killing them,
# so the next hang names its own blocked call stack in the CI log.
#
# Usage: scripts/ci-test.sh          (PALANA_TEST_TIMEOUT seconds, default 600)

set -uo pipefail

TIMEOUT="${PALANA_TEST_TIMEOUT:-600}"

# --no-parallel is not caution, it is the fix for a real contention bug:
# the ssh integration suites each open a master, and enough of them at once
# trips sshd's MaxStartups, which drops connections ("Connection closed by
# ... port 22") and, on a loaded runner, leaves some mid-handshake. It also
# makes any future hang attributable to exactly one named test.
swift test --enable-code-coverage --no-parallel &
TEST_PID=$!

(
    sleep "$TIMEOUT"
    if kill -0 "$TEST_PID" 2>/dev/null; then
        echo "::error::test run exceeded ${TIMEOUT}s — sampling before the kill"
        # The test binary, the SwiftPM driver, and anything they spawned.
        for pid in $(pgrep -f "PalanaPackageTests|swiftpm-testing|xctest|swift-test" 2>/dev/null); do
            echo "----- sample $pid ($(ps -o comm= -p "$pid" 2>/dev/null)) -----"
            sample "$pid" 3 -mayDie 2>&1 | head -120
        done
        echo "----- ssh processes still open -----"
        pgrep -fl "ssh " 2>/dev/null | head -20
        kill -9 "$TEST_PID" 2>/dev/null
    fi
) &
WATCHDOG=$!

wait "$TEST_PID"
STATUS=$?

kill "$WATCHDOG" 2>/dev/null
wait "$WATCHDOG" 2>/dev/null

exit "$STATUS"
