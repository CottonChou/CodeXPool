# macOS Release Workflow (Swift Migration)

## Prerequisites
- Xcode command line tools
- Apple Developer signing certificate (Developer ID Application)
- Optional notarization profile configured for `notarytool`

## Build + Sign + Notarize
```bash
cd swift-migration
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="your-notary-profile" \
./scripts/release_macos.sh
```

## Output
- Release artifacts are generated under `swift-migration/artifacts/`.
- If notarization profile is provided, `notarytool` is executed automatically.

## Notes
- This script produces a signed/notarized binary zip for distribution testing.
- For full `.app` bundle distribution, migrate this package target into an Xcode app project and run archive/export flow with the same identity/profile.
