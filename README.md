# Pocket Ledger

A native, personal iPhone expense tracker targeting **iOS 27**, with INR amounts, HDFC/ICICI/Axis UPI and card-message parsing, automatic saving through Apple Shortcuts, editable categories, and private iCloud sync.

## What is implemented

- Monthly spending overview, category breakdown, and recent activity.
- Monthly category budgets with spending progress for the selected month.
- Manual add/edit/delete, searchable transactions, type/category filters.
- On-device bank-message parser and the **Import Bank Message** App Intent.
- Automatic saving of recognized expenses, refunds, income, and card repayments.
- Review flags for uncertain merchants, banks, payment methods, dates, and UPI transfer ambiguity. Saved review items are included in totals.
- Category creation, renaming, icons, colors, ordering, and archiving.
- Remembered merchant rules, with built-in suggestions as a fallback.
- SwiftData persistence and private CloudKit configuration for the same Apple Account.
- Duplicate suppression, deletion tombstones, and deterministic display of records imported independently on different devices.
- CSV export and restore with a preview, duplicate detection, category metadata, and deleted-transaction recovery; optional Face ID/device-passcode screen lock.
- No server, network parser, advertising, analytics, or third-party package dependencies.
- Settings → Appearance offers ten color themes and Follow system/Light/Dark display modes; preferences persist locally. The app icon features ₹.

## Open and run

1. Open **`PocketLedger.xcodeproj`** in Xcode. Choose the **PocketLedger** scheme in the top toolbar. Leave **PocketLedger iCloud** for later; your free Apple account cannot provision CloudKit.
2. In the menu bar, open **Xcode → Settings → Accounts**, click **+**, and sign in with your Apple Account. Xcode creates a **Personal Team** automatically.
3. In the left project navigator, click the blue **PocketLedger** project icon. Under **TARGETS**, select **PocketLedger** and open **Signing & Capabilities**. Enable **Automatically manage signing**, choose your **Personal Team**, and replace the Bundle Identifier `com.personal.pocketledger` with something unique, such as `com.yourname.pocketledger`. This can also be set through a local `Config/Personal.xcconfig` copied from the example, but the Xcode UI is easier for a first run. Keep the same identifier later to preserve your installed app's data.
4. Connect your iPhone by cable, unlock it, and tap **Trust** if prompted. It must run iOS 27 or later for this build. Select your iPhone next to the scheme name in Xcode's toolbar. If Xcode asks to prepare the device or enable **Developer Mode**, follow the prompt; on the iPhone the setting is **Settings → Privacy & Security → Developer Mode**. The phone restarts and asks you to confirm.
5. Press the triangular **Run** button, or **⌘R**. Xcode signs and installs the app. Open Pocket Ledger and add a manual ₹10 expense first. Close and reopen the app to confirm it was saved. Then try **Import SMS** by pasting a transaction message. Set up the Shortcuts automation after the app has launched once.

The project is also directly compilable by Xcode without resolving Swift packages; the same core/store source files are compiled into the iPhone target. `Package.swift` remains for automated checks. Full Xcode 27.1 compilation and 42 XCTest cases passed at the previous checkpoint; CSV restore and monthly budgets were added afterward and still need verification. Real-device signing and Shortcuts execution still require your iPhone and Apple Account.

The local scheme has no iCloud entitlement and can be used with a free Personal Team, subject to Apple's personal provisioning limits. The iCloud scheme requires a paid Apple Developer membership and a provisioned CloudKit container.

## Enable private iCloud

1. Use the same bundle identifier as the local build to retain its data.
2. Set `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, and `LEDGER_CLOUD_CONTAINER` in `Config/Personal.xcconfig`.
3. Select **PocketLedger iCloud**. Under Signing & Capabilities, enable/verify iCloud → CloudKit and select/create the exact container identifier; verify Push Notifications and Background Modes → Remote notifications.
4. Run the development build on two iPhones signed into the same Apple Account. Open both apps, make a transaction on one, and check the other after CloudKit processes changes.
5. Confirm categories, rules, edits, deletions, offline changes, and duplicate imports as described in `docs/DEVICE_TESTS.md`.

Both schemes use the same local store path. Switching schemes does not intentionally erase or migrate to a second store. Make a CSV export before experimenting with signing, account changes, or cloud configuration. Storage initialization failures are shown explicitly; the app never silently replaces the ledger with an empty/in-memory store.

CSV restore is under **Settings → Your data → Import transactions from CSV**. It previews new rows, duplicates, and invalid rows before saving. New exports carry stable transaction/category IDs and category appearance fields; older Pocket Ledger exports without those columns remain supported. Imported transaction records are deduplicated on repeat import. If the ledger contains a deletion tombstone for a backed-up row, explicitly importing that CSV restores it as a new logical record. CSV restores transactions and the categories represented by those transactions; it does not restore merchant rules, monthly budgets, or categories with no transactions. Monthly category limits are set under **Settings → Make it yours → Monthly category budgets** and appear in the Overview breakdown for that month.

CloudDebug uses the Development CloudKit environment. CloudRelease/archives use Production; deploy the CloudKit schema to Production before TestFlight or distribution. Personal device testing only needs CloudDebug. Sync is eventual, not instant. The UI reports observed CloudKit activity and account availability rather than claiming every record is up to date.

## Set up SMS imports

See **Settings → Automatic imports** in the app or [`docs/SHORTCUTS.md`](docs/SHORTCUTS.md).

The app cannot read the Messages inbox directly. You create a personal Message automation in Shortcuts, pass the message content into **Pocket Ledger → Import Bank Message**, and enable running without confirmation. Raw message text stays in memory; only parsed transaction details and a SHA-256 duplicate fingerprint are persisted.

## Verification

With Xcode selected:

```sh
sh scripts/check.sh
```

`check.sh` runs the XCTest suite, validates the project/resources, and compiles the unsigned iPhone build. The command includes `-disable-sandbox` for Swift's compiler subprocesses because this automated workspace already applies its own sandbox. Xcode's normal **Run** button handles the usual local build. The package's `PocketLedgerCheck` executable is a compile check only, not a supported Mac app or the iPhone distribution target.

With Command Line Tools only, the real parser and money code can still be compiled and exercised:

```sh
sh scripts/check-core.sh
python3 scripts/validate_project.py
```

See [`docs/VALIDATION.md`](docs/VALIDATION.md) for checks actually completed and outstanding device checks. Parser examples now include the ICICI message provided by the user and synthetic representative templates; other messages still need validation against your banks' wording.

## Limits and next validation

- Message formats vary. Unrecognized messages return an explanation and require manual entry; they are not silently stored as guessed expenses. A Shortcut notification using the result helps surface skipped messages.
- Mastercard/Visa are accepted as card indicators, but parsing primarily follows the issuing bank's text.
- UPI debits save automatically, with a review flag to distinguish purchases from transfers between your own accounts. Set the transaction type to Transfer when appropriate.
- Reference-based duplicate keys include bank, reference, type, and amount. Without a reference, normalized message text plus its transaction/receipt day is used. Two truly identical purchases on the same day with no distinguishing reference/time can collapse; add the second manually if that occurs. Different SMS wording without a shared reference can still produce duplicates.
- A refund on a later date reduces spending in the month the refund occurred; it does not rewrite the purchase month's totals.
- Direct private iCloud synchronization and locked-phone Shortcuts execution require real device validation. iOS controls execution and sync timing.
- Parser fixtures now include one confirmed ICICI card message. Other bank templates still need anonymized samples that retain the original wording, punctuation, and date/amount structure.
- If a previous build imported the ICICI sample but used its block-notification phone number as the merchant, update the app in Xcode and import that message again. The updated importer repairs that bad SMS-derived merchant instead of creating a duplicate.

## Source layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI screens, runtime, App Intent, assets and entitlements |
| `Sources/BudgetCore/` | Message parsing, money, transaction types, category suggestions |
| `Sources/BudgetStore/` | Versioned models, import service, projections, export |
| `Tests/` | Parser and persistence XCTest suites |
| `Config/` | Local/iCloud debug/release configurations |
| `scripts/` | Checks and deterministic Xcode project generation |

After adding or removing Swift files in `App/` or `Sources/`, run `python3 scripts/generate_project.py`. It rewrites project source references and shared schemes; keep personal signing settings in `Personal.xcconfig`.
