# Releasing pālana

How a signed, notarized `.dmg` gets built and published. pālana is pure Swift on
SwiftPM — `Package.swift` stays canonical and `scripts/build_macos.sh` wraps the
build product in a `.app` by hand. No Xcode project.

## The sequence

1. **Build + sign + notarize** — run the build script locally, test the DMG
2. **Push the tag** — marks the release commit
3. **Create the GitHub Release** — attach the DMG; this is the public download

> Tagging is just a marker. The **GitHub Release** is what people download.

---

## Prerequisites

- macOS with the Xcode command-line tools
- **Developer ID Application** certificate in the login keychain
- A **notarytool keychain profile** holding the App Store Connect credentials.
  Create it once:
  ```bash
  xcrun notarytool store-credentials "palana-notary" \
      --apple-id "you@example.com" --team-id "3N8F759K8D"
  # (prompts for an app-specific password)
  ```
- An app icon at `packaging/palana.png` (1024×1024; the script builds the `.icns`)
  or a ready-made `packaging/palana.icns`.

---

## Step 1 — Build, sign, notarize

```bash
export CODESIGN_IDENTITY="Developer ID Application: ANDREW TODD MARCUS (3N8F759K8D)"
export NOTARIZE_KEYCHAIN_PROFILE="palana-notary"

# VERSION and DMG_SUFFIX default to 0.4.0 and "beta".
# Override per release, e.g.:  VERSION=1.0.0 DMG_SUFFIX="" ./scripts/build_macos.sh --dmg
./scripts/build_macos.sh --dmg
```

The script builds universal (arm64 + x86_64), assembles `dist/Palana.app`, signs
inside-out (executable then bundle, never `--deep`), packages `dist/palana-<v>.dmg`
with `ditto`, submits to notarytool `--wait`, and staples.

Verify after it finishes:
```bash
codesign --verify --deep --strict dist/Palana.app
spctl --assess --type open --context context:primary-signature -v dist/palana-*.dmg
```

Open the DMG, drag to Applications, launch it, and click through before publishing.

### Signing rules that must not change

- **Never use `codesign --deep`** — it signs nested code in the wrong order and
  invalidates it. The script signs the executable, then the bundle.
- **Use `ditto` for DMG staging, not `cp -r`** — `cp -r` follows symlinks and
  corrupts the bundle, breaking the signature and notarization.
- **Notarize the DMG, not the app** — submit the `.dmg` to notarytool.
- **Staple after notarization** — `xcrun stapler staple dist/<name>.dmg`.
- **Hardened runtime, empty entitlements** — `scripts/entitlements.plist` is
  deliberately empty (pure Swift, no dynamically-loaded code). Add an entitlement
  only when a concrete capability needs it, with a comment saying why.

---

## Step 2 — Tag

```bash
git push origin main
git tag v<version>          # e.g. v0.4-beta
git push origin v<version>
```

---

## Step 3 — Create the GitHub Release

```bash
gh release create v<version> dist/palana-<version>-*.dmg \
    --title "v<version>" \
    --notes "<what's in this build; for a beta, name what isn't yet>"
```

Mark pre-1.0 builds as prereleases (`--prerelease`). A beta must say plainly
what's missing — as of v0.4-beta, the ZFS workbench tool and the interactive
terminal are not yet in.
