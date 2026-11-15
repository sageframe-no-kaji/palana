# Releasing pālana

This document describes how a signed, notarized `.dmg` is built and published.
pālana is pure Swift on SwiftPM. `Package.swift` stays canonical, and
`scripts/build_macos.sh` wraps the build product in a `.app` bundle by hand.
There is no Xcode project.

## The sequence

1. **Build, sign, and notarize** the DMG locally, then test it.
2. **Sell the DMG on Payhip:** replace the file on the pālana product.
3. **Tag the release and publish a GitHub release with notes only.** The in-app
   update check reads its tag.
4. **Update the site** so its version and Buy button match the release.

> The update check (`Sources/Palana/UpdateChecker.swift`) asks GitHub's
> latest-release endpoint for the newest tag at launch. When that tag is newer
> than the running app's `CFBundleShortVersionString`, the app shows the update
> and links to [palana.sageframe.net](https://palana.sageframe.net), never to a
> GitHub download. For the check to see a release, publish it as GitHub's normal
> Latest release, not as a prerelease or a draft. Tag it `v` followed by one to
> three whole numbers separated by dots (`v1.0`, `v1.0.1`, `v1.1`). Missing
> trailing numbers count as zero, so `v1.0` equals the bundle version `1.0.0`. A
> tag with a suffix such as `v1.1-beta` sorts below `v1.1`.

---

## Prerequisites

- macOS with the Xcode command-line tools
- A **Developer ID Application** certificate in the login keychain
- A **notarytool keychain profile** that holds the App Store Connect
  credentials. Create it once:
  ```bash
  xcrun notarytool store-credentials "palana-notary" \
      --apple-id "you@example.com" --team-id "3N8F759K8D"
  # (prompts for an app-specific password)
  ```
  Do not pass `--password` on that command line. Without it, notarytool prompts
  for the password, so the password never lands in shell history.
- The app icon at `packaging/palana.png` (1024×1024; the script builds the
  `.icns` from it) or a ready-made `packaging/palana.icns`.

---

## Step 1: Build, sign, notarize

```bash
export CODESIGN_IDENTITY="Developer ID Application: ANDREW TODD MARCUS (3N8F759K8D)"
export NOTARIZE_KEYCHAIN_PROFILE="palana-notary"

# VERSION defaults to 1.0.0 and DMG_SUFFIX defaults to "" (no suffix).
# Override them per release, for example:
#   VERSION=1.0.1 ./scripts/build_macos.sh --dmg
./scripts/build_macos.sh --dmg
```

The script builds arm64 and x86_64 separately and merges them with `lipo` into
one universal executable. It assembles `dist/Palana.app`, writes the
Info.plist, and signs inside-out (the executable, then the bundle, never
`--deep`). It then notarizes and staples the app, packages
`dist/palana-<version>.dmg` from the stapled app with `ditto`, and notarizes and
staples the DMG.

A non-empty `DMG_SUFFIX` (the betas used `beta`) adds the suffix to the DMG name
and records it as the release channel that About and Settings display. Leave it
empty for a release.

Other forms:

```bash
./scripts/build_macos.sh                    # universal .app only, no DMG
ARCH_FLAGS="" ./scripts/build_macos.sh      # native-only .app, a quick local build
./scripts/build_macos.sh --clean            # remove dist/ only
```

Without `CODESIGN_IDENTITY`, the app is signed ad hoc for local use only, and
the script says so. Without `NOTARIZE_KEYCHAIN_PROFILE`, the DMG is not
notarized. Neither passes Gatekeeper on another Mac.

### Verify the build

```bash
lipo -archs dist/Palana.app/Contents/MacOS/Palana          # arm64 and x86_64
codesign --verify --deep --strict --verbose=2 dist/Palana.app
xcrun stapler validate dist/Palana.app
xcrun stapler validate dist/palana-*.dmg
spctl --assess --type execute -v dist/Palana.app
```

Open the DMG, drag pālana to Applications, launch it, and click through it
before you publish.

### Signing rules that must not change

- **Never use `codesign --deep`.** It signs nested code in the wrong order and
  invalidates it. The script signs the executable, then the bundle.
- **Use `ditto` for DMG staging, not `cp -r`.** `cp -r` follows symlinks and
  corrupts the bundle, which breaks the signature and notarization.
- **Notarize both layers.** Notarize and staple the app before it goes into the
  DMG, then notarize and staple the DMG.
- **Hardened runtime, empty entitlements.** `scripts/entitlements.plist` is
  empty on purpose: pālana is pure Swift with no dynamically loaded code. Add an
  entitlement only when a concrete capability needs it, with a comment that says
  why.

---

## Step 2: Payhip

Upload `dist/palana-<version>.dmg` to the pālana product on Payhip, replacing
the previous file. The product page copy is in the website repository at
`design/payhip/payhip-listing.md`. The price is US $29 and covers all 1.x
updates. There is no license key or activation to configure.

## Step 3: Tag and publish the release notes

```bash
git push origin main
git tag -a v<version> -m "pālana <version>"     # for example, v1.0
git push origin v<version>
gh release create v<version> \
    --verify-tag \
    --latest \
    --title "pālana <version>" \
    --notes-file packaging/release-notes-v<version>.md
```

Attach no DMG. The signed app is sold through the site, and the source is free
to build. Do not pass `--prerelease`, because GitHub excludes prereleases from
the latest-release endpoint that pālana checks.

## Step 4: The site

Update [palana.sageframe.net](https://palana.sageframe.net) (the
`sageframe-dharma/palana-web` repository): set `version` in
`public/_data/site.json`, confirm that `buyUrl` points to the Payhip product,
build, and publish. Point the site's release notes at the exact GitHub release
page. The Help menu, the About panel, and the update notice all link to the
site.
