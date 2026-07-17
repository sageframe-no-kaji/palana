# Releasing pālana

How a signed, notarized `.dmg` gets built and published. pālana is pure Swift on
SwiftPM — `Package.swift` stays canonical and `scripts/build_macos.sh` wraps the
build product in a `.app` by hand. No Xcode project.

## The sequence

1. **Build + sign + notarize** — run the build script locally, test the DMG
2. **Upload the DMG to Payhip** — this is the download (the paid binary)
3. **Push the tag + a notes-only GitHub Release** — the public version marker
4. **Update the site** — `palana.sageframe.net` carries the buy button + changelog

> The **binary is sold on Payhip**, not attached to a public GitHub download.
> The GitHub Release is notes-only (tag + changelog + a link to the site); the
> in-app update check reads that tag for the version and points the operator at
> the site. Keep them in lockstep: a new tag means a new Payhip upload.

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

# VERSION and DMG_SUFFIX default to 1.0.0 and "" (no suffix).
# Override per release, e.g.:  VERSION=1.1.0 ./scripts/build_macos.sh --dmg
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

## Step 2 — Upload to Payhip

The verified `dist/palana-<version>.dmg` is the product. Upload it to the Payhip
listing as the new version's file. This is what buyers download.

## Step 3 — Tag + a notes-only GitHub Release

```bash
git push origin main
gh release create v<version> \
    --title "pālana <version>" \
    --notes-file packaging/release-notes-<version>.md
```

**No binary is attached** — the notes point at `palana.sageframe.net` (Payhip).
The in-app update check reads this release's tag for the version, so a tag with no
release is invisible to it; always cut the release. Pre-1.0 builds are
`--prerelease`.

## Step 4 — The site

Update `palana.sageframe.net` (the `sageframe-dharma/palana` site): the download/
buy button to the new Payhip version, and the changelog. The Help menu, About,
and the update announce all point here.
