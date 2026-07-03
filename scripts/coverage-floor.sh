#!/usr/bin/env bash
# Enforces the PalanaCore line-coverage floor (default 90%).
# Assumes `swift test --enable-code-coverage` has already run.
# The Palana app target and Tests are excluded — the floor lives in the
# core because the truth lives in the core.

set -euo pipefail

FLOOR="${1:-90}"
PROFDATA=.build/debug/codecov/default.profdata
BINARY=.build/debug/PalanaPackageTests.xctest/Contents/MacOS/PalanaPackageTests

xcrun llvm-cov report "$BINARY" \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex='(Tests/|\.build/|Sources/Palana/)'

xcrun llvm-cov export "$BINARY" \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex='(Tests/|\.build/|Sources/Palana/)' \
    -summary-only \
    | python3 -c "
import json, sys
percent = json.load(sys.stdin)['data'][0]['totals']['lines']['percent']
print(f'PalanaCore line coverage: {percent:.2f}% (floor: $FLOOR%)')
sys.exit(0 if percent >= $FLOOR else 1)
"
