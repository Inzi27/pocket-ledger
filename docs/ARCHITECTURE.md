# Implementation notes

## Import path

`Shortcuts → ImportMessageIntent → MessageParser → LedgerStore → SwiftData → private CloudKit`

The intent runs in the app process without opening the foreground UI and allows execution while locked. It shares the main-actor store with the UI, serializing local imports. The store directory uses complete-until-first-user-authentication file protection on iOS; this allows imports after the first unlock following a restart. The optional app lock protects the UI and does not block background saves. iOS remains responsible for scheduling the automation.

Parsing is deterministic and on-device. Amounts are integer paise. Input length is bounded. Recognized transactions are saved immediately; uncertainty produces a review reason. Unknown formats return a reason without storing full message text. No remote inference service is used.

## Persistence and sync

Schema V2 contains `LedgerEntry`, `LedgerCategory`, `MerchantRule`, and `MonthlyBudget`. V2 adds monthly category limits through a lightweight migration from V1. Stored properties have defaults, and there are no unique constraints or required relationships. Category links use stable string identifiers, avoiding CloudKit relationship arrival-order assumptions. Future schema changes must add a new version and an appropriate migration stage.

CloudKit cannot enforce the logical uniqueness needed here. Every physical record has its own UUID, while imported transactions have a stable logical ID derived from a reference or normalized message. Views, totals, and exports use a projection selecting the latest logical copy, with deterministic tie-breaking. Deletion wins across duplicate copies; minimal tombstones prevent reimport resurrection. The physical duplicate rows are not aggressively garbage-collected because a late offline device could otherwise reintroduce them.

Default category IDs are deterministic. Seed records have an epoch modification timestamp, so user edits win over independently seeded copies from another device. User-created categories have UUIDs. Merchant rules match normalized merchant names exactly; the latest edit wins. Archiving a category retains history while disabling assignment to new imports.

The app observes actual Core Data CloudKit events and account availability. It does not offer a misleading synchronous ‘sync now’ guarantee. No failed-store fallback creates a replacement ledger. Sync behavior follows [Apple's SwiftData guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) and [CloudKit model constraints](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit).

## Scope

The app uses one currency, one person's Apple Account, and iPhone screens. It does not include receipt OCR, direct bank connections, household sharing, statement import, or exchange-rate conversion. CSV restore covers transactions and categories represented by those transactions; it is not a complete app-data backup.
