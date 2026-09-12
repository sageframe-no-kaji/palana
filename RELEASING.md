# Releasing pālana

How a signed, notarized `.dmg` gets built and published. pālana is pure Swift on
SwiftPM — `Package.swift` stays canonical and `scripts/build_macos.sh` wraps the
build product in a `.app` by hand. No Xcode project.

## The sequence

1. **Build + sign + notarize** — run the build script locally, test the DMG
2. **Push the tag + GitHub Release** — attach the beta DMG and publish it as Latest
3. **Update the site** — link Download directly to the versioned DMG asset

> Public beta binaries are attached directly to GitHub Releases. Publish the beta
> as GitHub's normal Latest release, not as a GitHub prerelease: the in-app update
> check reads GitHub's latest-release endpoint. The release name and tag still
> identify the build as beta.

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
- **Notarize both layers** — notarize and staple the app before placing it in
  the DMG, then notarize and staple the DMG.
- **Hardened runtime, empty entitlements** — `scripts/entitlements.plist` is
  deliberately empty (pure Swift, no dynamically-loaded code). Add an entitlement
  only when a concrete capability needs it, with a comment saying why.

---

## Step 2 — Tag and publish the beta

```bash
git push origin main
git tag -a v<version> -m "pālana <version>"  # e.g. v0.8-beta
git push origin v<version>
gh release create v<version> \
    dist/palana-<numeric-version>-beta.dmg \
    --verify-tag \
    --latest \
    --title "pālana <version>" \
    --notes-file packaging/release-notes-<version>.md
```

Do not pass `--prerelease` for the public beta. GitHub excludes prereleases from
the latest-release endpoint that pālana checks on launch.

## Step 3 — The site

Update `palana.sageframe.net` (the `sageframe-dharma/palana` site): point the
primary button directly at the versioned GitHub DMG asset, and point release
notes at the exact GitHub release page. The Help menu, About, and update announce
all point to the site.
