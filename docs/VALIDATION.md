# Validation status

## Completed in this workspace

- Xcode 27.1 with the iOS 27.1 SDK is installed and selected.
- The unsigned iPhone build succeeded using `xcodebuild` for the **PocketLedger** local-storage scheme and generic iOS device target.
- SwiftPM compiled the shared UI and ran **42 XCTest cases**, all passing: 31 parser/money checks and 11 storage, import, deletion, merchant rule, export, and projection checks.
- The standalone parser check passed 33 representative cases.
- Validated the Xcode project, registered source files, two schemes, property lists, entitlements, privacy manifest, and asset metadata. Inspected the app icon.

The automated workspace requires `OTHER_SWIFT_FLAGS=-disable-sandbox` for Xcode's macro-plugin subprocesses. This is a restriction of the automation sandbox; the normal Xcode UI build may not need that flag. The iOS Simulator service is unavailable to this automation session, so no screenshots or simulator interactions were verified.

## Still needs a real iPhone

- Signing with the user's Personal Team, installing and opening the app, checking screen layout and accessibility.
- A real incoming Message automation, including while the phone is locked and after its first unlock following a restart.
- Anonymized real bank-message samples to confirm HDFC, ICICI, and Axis templates match their current wording.
- Private iCloud sync, if a paid Apple Developer Program membership is added later.

The user-provided ICICI message has been parsed with the corrected merchant extraction and verified by a regression test. It imports as ₹209.00 for `RSP*SWIGGY PVT`, ICICI card ending 9003, transaction date 25-Oct-26, category Food. Re-import also repairs the specific older bad result where the card-block phone was stored as the merchant.

Run `sh scripts/check.sh` to repeat the unsigned build and automated tests. Then follow [the device checklist](DEVICE_TESTS.md) for the remaining checks.
