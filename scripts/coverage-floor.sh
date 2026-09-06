#!/usr/bin/env bash
# Enforces two line-coverage floors. Assumes `swift test --enable-code-coverage`
# has already run.
#
#   1. PalanaCore ≥ $1 (default 90) — the engine. The truth lives in the core.
#   2. Application logic ≥ $2 (default 35) — the non-rendering half of the
#      Palana target: the operation flow and its record, the round-trip
#      center, settings, the pane and session models, the stores. Measured
#      at 37% on 2026-09-06 when this floor was set (review finding: the
#      gate excluded the whole application layer, so the highest-risk state
#      transitions ran unmeasured). Ratchet this number up as tests land;
#      never down.
#
# The application set is everything under Sources/Palana EXCEPT files that
# match RENDERING_PATTERN — pure SwiftUI/AppKit drawing, named by shape:
# the App entry, windows, views, panels, overlays, bars, buttons, chips,
# cards, forms, strips, the theme, the column and wash helpers, and the
# outward-link table. Anything not matched is measured. Adding a name to
# the pattern is a reviewed decision, and REQUIRED_APP_FILES below refuses
# to let the safety-critical orchestration slip out of the measured set:
# an exclusion that swallows OperationModel passes nothing.

set -euo pipefail

CORE_FLOOR="${1:-90}"
APP_FLOOR="${2:-35}"
PROFDATA=.build/debug/codecov/default.profdata
BINARY=.build/debug/PalanaPackageTests.xctest/Contents/MacOS/PalanaPackageTests

CORE_IGNORE='(Tests/|\.build/|Sources/Palana/)'

RENDERING_PATTERN='Sources/Palana/(App|AboutWindow|Theme|TableSelectionStyler|DropWash|PaneColumns|Links|[^/]*View[^/]*|[^/]*Panel[^/]*|[^/]*Overlay[^/]*|[^/]*Bar|[^/]*Button|[^/]*Chip|[^/]*Card[^/]*|[^/]*Form|[^/]*Strip)\.swift'
APP_IGNORE="(Tests/|\\.build/|Sources/PalanaCore/|${RENDERING_PATTERN})"

# The files the application floor exists for. The gate fails if any of
# them is missing from the measured set, whatever the percentage says.
REQUIRED_APP_FILES="OperationModel.swift OperationLog.swift RoundTripCenter.swift SettingsModel.swift PaneModel.swift PalanaSession.swift"

echo "== PalanaCore =="
xcrun llvm-cov report "$BINARY" \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex="$CORE_IGNORE"

echo
echo "== Application logic (Sources/Palana minus rendering) =="
xcrun llvm-cov report "$BINARY" \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex="$APP_IGNORE"

check_floor() {
    local label="$1" ignore="$2" floor="$3" required="$4"
    xcrun llvm-cov export "$BINARY" \
        -instr-profile "$PROFDATA" \
        -ignore-filename-regex="$ignore" \
        -summary-only \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)['data'][0]
files = [f['filename'] for f in data['files']]
names = {name.rsplit('/', 1)[-1] for name in files}
missing = [name for name in '$required'.split() if name not in names]
if not files:
    print('$label: no files measured — the gate cannot pass on an empty set')
    sys.exit(1)
if missing:
    print('$label: required files missing from the measured set: ' + ', '.join(missing))
    sys.exit(1)
percent = data['totals']['lines']['percent']
print(f'$label line coverage: {percent:.2f}% over {len(files)} files (floor: $floor%)')
sys.exit(0 if percent >= $floor else 1)
"
}

echo
check_floor "PalanaCore" "$CORE_IGNORE" "$CORE_FLOOR" ""
check_floor "Application logic" "$APP_IGNORE" "$APP_FLOOR" "$REQUIRED_APP_FILES"
