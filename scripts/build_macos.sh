#!/usr/bin/env bash
# build_macos.sh — build Palana.app and (optionally) a signed, notarized .dmg
#
# Usage:
#   ./scripts/build_macos.sh            # build the universal .app
#   ./scripts/build_macos.sh --dmg      # build .app + .dmg (+ notarize if creds set)
#   ./scripts/build_macos.sh --clean    # wipe dist/ only
#
# pālana is pure Swift on SwiftPM. Package.swift stays canonical — this script
# wraps the `swift build` product in a proper .app bundle by hand, signs it, and
# packages a .dmg. No Xcode project required.
#
# For a signed + notarized release build, set:
#   export CODESIGN_IDENTITY="Developer ID Application: ANDREW TODD MARCUS (3N8F759K8D)"
#   export NOTARIZE_KEYCHAIN_PROFILE="<notarytool profile name stored in keychain>"
#
# Icon: drop a 1024x1024 PNG at packaging/palana.png (this script builds the
# .icns) or a ready-made packaging/palana.icns. Absent either, the app ships
# with the generic icon and the script warns.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Palana"                       # .app filename (ASCII, no diacritic)
DISPLAY_NAME="pālana"                   # shown in Finder / menu bar / About
BUNDLE_ID="com.sageframe.palana"
VERSION="${VERSION:-0.4.0}"             # CFBundleShortVersionString (numeric)
DMG_SUFFIX="${DMG_SUFFIX:-beta}"        # trailing label on the dmg name; "" to omit
MIN_MACOS="14.0"

if [[ -n "$DMG_SUFFIX" ]]; then
    DMG_NAME="palana-${VERSION}-${DMG_SUFFIX}.dmg"
else
    DMG_NAME="palana-${VERSION}.dmg"
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
BUILD_DMG=false
CLEAN_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --dmg)   BUILD_DMG=true ;;
        --clean) CLEAN_ONLY=true ;;
    esac
done

# ── Clean ─────────────────────────────────────────────────────────────────────
echo "==> Cleaning dist/"
rm -rf dist
if $CLEAN_ONLY; then
    echo "==> Clean done."
    exit 0
fi

# ── Build (universal2) ────────────────────────────────────────────────────────
echo "==> Building ${APP_NAME}  (version ${VERSION}, universal arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN" ]]; then
    echo "ERROR: built executable not found at $BIN"
    exit 1
fi
echo "    Built: $BIN"
file "$BIN" | grep -q "universal binary" \
    && echo "    Verified universal2" \
    || echo "    WARNING: executable is not universal2"

# ── Assemble the .app bundle ──────────────────────────────────────────────────
APP_PATH="dist/${APP_NAME}.app"
echo "==> Assembling ${APP_PATH}"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN" "$APP_PATH/Contents/MacOS/$APP_NAME"

# Icon: prefer a ready .icns; else build one from a 1024x1024 PNG.
ICON_KEY=""
if [[ -f "packaging/palana.icns" ]]; then
    cp "packaging/palana.icns" "$APP_PATH/Contents/Resources/palana.icns"
    ICON_KEY="palana"
elif [[ -f "packaging/palana.png" ]]; then
    echo "    Building palana.icns from packaging/palana.png"
    ICONSET="$(mktemp -d)/palana.iconset"
    mkdir -p "$ICONSET"
    for sz in 16 32 64 128 256 512; do
        sips -z "$sz" "$sz"       "packaging/palana.png" --out "$ICONSET/icon_${sz}x${sz}.png"   >/dev/null
        sips -z "$((sz*2))" "$((sz*2))" "packaging/palana.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/palana.icns"
    rm -rf "$(dirname "$ICONSET")"
    ICON_KEY="palana"
else
    echo "    WARNING: no packaging/palana.icns or packaging/palana.png — shipping the generic icon"
fi

# Info.plist (version single-sourced from $VERSION above).
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>       <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>        <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>  <string>Andrew Marcus — GPL-3.0</string>$(
        [[ -n "$ICON_KEY" ]] && printf '\n    <key>CFBundleIconFile</key>          <string>%s</string>' "$ICON_KEY"
    )
</dict>
</plist>
PLIST
echo "    Wrote Info.plist"

# ── Codesign ──────────────────────────────────────────────────────────────────
# Native Swift: one executable, no framework tree. Sign the binary, then the
# bundle. Never --deep (signs inner code in the wrong order, invalidating it).
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "==> Signing with identity: $CODESIGN_IDENTITY"
    ENTITLEMENTS="$SCRIPT_DIR/entitlements.plist"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_PATH/Contents/MacOS/$APP_NAME"
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
        && echo "==> Signature verified OK"
else
    echo "==> Ad-hoc signing (local use only — will not pass Gatekeeper on other Macs)"
    codesign --force --sign - "$APP_PATH"
fi

# ── DMG ───────────────────────────────────────────────────────────────────────
if $BUILD_DMG; then
    echo "==> Creating $DMG_NAME"
    STAGING="$(mktemp -d)"
    # ditto, not cp -r — preserves bundle structure and code signatures.
    ditto "$APP_PATH" "$STAGING/$(basename "$APP_PATH")"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create \
        -volname "$DISPLAY_NAME" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "dist/$DMG_NAME"
    rm -rf "$STAGING"
    echo "==> DMG: dist/$DMG_NAME"

    # ── Notarize (only if a keychain profile is configured) ────────────────────
    if [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
        echo "==> Submitting for notarization (keychain profile: $NOTARIZE_KEYCHAIN_PROFILE)…"
        xcrun notarytool submit "dist/$DMG_NAME" \
            --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" \
            --wait
        xcrun stapler staple "dist/$DMG_NAME"
        echo "==> Notarization complete and stapled."
        echo "==> Gatekeeper assessment:"
        spctl --assess --type open --context context:primary-signature --verbose=2 "dist/$DMG_NAME" || true
    else
        echo "==> NOTE: NOTARIZE_KEYCHAIN_PROFILE unset — .dmg is signed but NOT notarized."
        echo "          It will hit Gatekeeper on other Macs until notarized."
    fi
fi

echo ""
echo "==> Done. Output:"
ls -lh dist/
