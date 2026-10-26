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
# Latest verification — 26 October 2026

`sh scripts/check.sh` passed after complete backup/restore, import activity, transaction date navigation, and card/payment views were implemented:

- 53 XCTest cases passed: 31 parser/money tests and 22 storage/CSV/enhancement tests.
- The nine new enhancement tests verify a complete backup round trip (including unused archived categories, rules, budgets, card nicknames, exact notes/review metadata, and activity), repeat restore after two deletion cycles with linked history, preserving existing edits, malformed backup rejection, import outcomes without raw SMS, explicit category-rule priority, date-range boundaries, card grouping, and migration/reopen of an existing V2 disk store into V3.
- Project validation passed for all 20 source files/resources/schemes.
- Unsigned generic iPhone Debug build succeeded with Xcode 27.1 / iOS 27.1 SDK.
- Full check log: `.build/enhancements-final-check.log`. Final iPhone build after lookup optimizations: `.build/enhancements-ios-final.log`.

Restored the Mac compile-check path by guarding UIKit and navigation-bar-only usage, supplying the macOS chart background, and importing BudgetCore in Settings. Existing sandbox CoreData notification/CoreSimulator diagnostics do not fail these local-store tests or the generic iPhone build. No physical-device UI, document picker, locked-phone Shortcut execution, or CloudKit runtime test was performed. No installed user ledger was modified.

Earlier sections above are historical checkpoints.
