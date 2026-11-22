# Releasing pālana

Build the release from the commit the maintainer has tested and approved. The Swift package manifest, `Package.swift`, defines the executable. The packaging script assembles the app bundle and disk image.

For the first 1.0 release, publish in this order once the maintainer authorizes release.

1. Prepare the Settings and keyboard-reference screenshots and the recorded tour.
2. Build, sign, notarize, and test the final disk image from `main`.
3. Create the Payhip product and upload the verified disk image.
4. Publish the website with the real product URL and check the live site.
5. Retire the beta disk-image assets from the v0.8-beta and v0.4-beta releases.
6. Tag the tested commit and publish the 1.0 release notes last.

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

## Build, sign, and notarize

The packaging script clears `dist/` before every build. Save any candidate you still need to compare before running it.

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
`dist/palana-<version>.dmg` by staging the app with `ditto` and creating the image with `hdiutil`, signs the DMG
with the same identity, and notarizes and staples the DMG. Notarizing a signed
app inside an unsigned DMG is not enough: Gatekeeper rejects the container.

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
codesign --verify --strict --verbose=2 dist/palana-*.dmg
spctl --assess --type execute -v dist/Palana.app
spctl --assess --type open --context context:primary-signature -v dist/palana-*.dmg
```

Open the DMG, drag pālana to Applications, launch it, and click through it
before you publish.

### Signing rules that must not change

- Sign the executable first and the bundle second. Use `--deep` only for verification.
- Stage the signed bundle with `ditto` to preserve its structure.
- **Notarize both layers.** Notarize and staple the app before it goes into the
  DMG, then notarize and staple the DMG.
- **Hardened runtime, empty entitlements.** `scripts/entitlements.plist` is
  empty on purpose: pālana is pure Swift with no dynamically loaded code. Add an
  entitlement only when a concrete capability needs it, with a comment that says
  why.

---

## Publish the build and site

The [pālana product on Payhip](https://payhip.com/b/YZKXE) holds the approved listing. For an update, upload the verified release file to that product. The website repository’s `design/payhip/` directory contains the gallery assets. The price is US $29 and includes all 1.x updates.

In `sageframe-dharma/palana-web`, set `version` and the real Payhip `buyUrl` in `public/_data/site.json`. Check that the application README, release notes, and website identify the same build and link to the same product. Run `npm run build` and check the purchase link. A push to the site’s `main` branch publishes it. Verify that the live purchase link opens the intended product and that `/.git/HEAD` returns 404.

## Tag the tested commit and publish the notes

The 1.0.0 disk image was built from `74be760`. PR #20 subsequently changed the application on `main`. For this image, tag the build commit or a documentation-only successor with the same application source and packaging inputs. The commands below assume you have checked out that intended revision and committed the final notes. Publish a regular GitHub release with notes only. At launch, the app reads GitHub’s latest release tag and links to the product site if the tag is newer than the running bundle version. Drafts and prereleases do not appear at that endpoint.

```bash
git tag -a v1.0 -m "pālana 1.0.0" HEAD
git push origin v1.0
gh release create v1.0 --verify-tag --latest \
    --title "pālana 1.0" --notes-file packaging/release-notes-v1.0.md
```

Use a tag with one to three numeric components after the initial `v`. The update checker treats omitted trailing components as zero, so `v1.0` matches bundle version `1.0.0`.
