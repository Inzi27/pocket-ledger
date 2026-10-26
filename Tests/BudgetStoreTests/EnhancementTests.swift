import XCTest
import SwiftData
import BudgetCore
@testable import BudgetStore

@MainActor final class EnhancementTests: XCTestCase {
    private let sms = "INR 209.00 spent using ICICI Bank Card XX9003 on 25-Oct-26 on RSP*SWIGGY PVT . Avl Limit: INR 9,76,331.63. If not you, call 1800 2662/SMS BLOCK 9003 to 9215676766"
    private let date = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
    private func store() throws -> ModelContainer {
        let container = try LedgerStore.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        try LedgerStore.seedCategories(in: container.mainContext)
        return container
    }

    func testImportHistoryRecordsOutcomesAndPreservesManualCategory() throws {
        let container = try store(); let context = container.mainContext
        _ = try LedgerStore.importMessage(sms, receivedAt: date, origin: "shortcut", in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEntry>()).first)
        entry.categoryID = "shopping"; entry.notes = "My correction"; try context.save()
        XCTAssertEqual(try LedgerStore.importMessage(sms, receivedAt: date, in: context), .duplicate)
        _ = try LedgerStore.importMessage("OTP 123456 for INR 500 HDFC card purchase", in: context)
        _ = try LedgerStore.importMessage("Unrecognized test message", in: context)
        let fresh = ModelContext(container)
        let events = try fresh.fetch(FetchDescriptor<ImportActivity>())
        XCTAssertEqual(Set(events.map(\.status)), ["saved", "duplicate", "ignored", "unrecognized"])
        XCTAssertEqual(events.first { $0.status == "saved" }?.origin, "shortcut")
        XCTAssertEqual(events.first { $0.status == "saved" }?.entryID, entry.id)
        XCTAssertFalse(events.contains { $0.detail.contains("123456") || $0.detail.contains("9215676766") || $0.detail.contains(sms) })
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<LedgerEntry>()).first?.categoryID, "shopping")
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<LedgerEntry>()), 1)
    }

    func testCompleteBackupRoundTripIncludesUnusedArchivedCategoriesAndMetadata() throws {
        let source = try store(); let context = source.mainContext
        let food = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.id == "food" })
        food.name = "Eating out"; food.tint = "red"; food.updatedAt = date
        let unused = LedgerCategory(id: "unused", name: "Unused category", symbol: "gift.fill", tint: "purple", order: 99)
        unused.isArchived = true; context.insert(unused)
        _ = try LedgerStore.importMessage(sms, receivedAt: date, origin: "shortcut", in: context)
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEntry>()).first)
        original.notes = "Comma, quote \" and newline\n₹"; original.reviewReason = "Check custom details"
        original.createdAt = date; original.updatedAt = date
        try LedgerStore.remember(merchant: original.merchant, categoryID: "food", in: context)
        try LedgerStore.setBudget(categoryID: "food", monthKey: "2026-10", amountPaise: 250000, in: context)
        try LedgerStore.setNickname("Everyday card", for: PaymentGroup.key(for: original), in: context)
        let data = try FullBackup.export(in: context)
        let backup = try FullBackup.decode(data)
        XCTAssertEqual(backup.categories.count, CategoryTemplate.defaults.count + 1)
        let target = try store()
        let result = try FullBackup.restore(backup, in: target.mainContext)
        XCTAssertEqual(result.transactions, 1); XCTAssertEqual(result.budgets, 1)
        XCTAssertEqual(result.rules, 1); XCTAssertEqual(result.accounts, 1); XCTAssertEqual(result.activities, 1)
        let fresh = ModelContext(target)
        let restored = try XCTUnwrap(fresh.fetch(FetchDescriptor<LedgerEntry>()).first)
        XCTAssertEqual(restored.id, original.id); XCTAssertEqual(restored.amountPaise, 20900)
        XCTAssertEqual(restored.notes, original.notes); XCTAssertEqual(restored.reviewReason, original.reviewReason)
        XCTAssertEqual(restored.createdAt, date); XCTAssertEqual(restored.updatedAt, date)
        XCTAssertEqual(restored.accountSuffix, "9003"); XCTAssertEqual(restored.bank, .icici)
        let cats = try fresh.fetch(FetchDescriptor<LedgerCategory>())
        XCTAssertEqual(cats.first { $0.id == "food" }?.name, "Eating out")
        XCTAssertEqual(cats.first { $0.id == "unused" }?.isArchived, true)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<PaymentAccount>()).first?.nickname, "Everyday card")
        let repeated = try FullBackup.restore(backup, in: target.mainContext)
        XCTAssertEqual(repeated.transactions, 0); XCTAssertEqual(repeated.skippedTransactions, 1)
        XCTAssertEqual(repeated.rules + repeated.budgets + repeated.accounts + repeated.activities, 0)
    }

    func testExplicitUncategorizedRuleWinsOverDeepScan() throws {
        let container = try store()
        try LedgerStore.remember(merchant: "RSP*SWIGGY PVT", categoryID: "other", in: container.mainContext)
        _ = try LedgerStore.importMessage(sms, receivedAt: date, in: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<LedgerEntry>()).first?.categoryID, "other")
    }

    func testRestoreRecoversDeletedTransactionsAndRemainsRepeatableAfterSecondDeletion() throws {
        let container = try store(); let context = container.mainContext
        _ = try LedgerStore.importMessage(sms, receivedAt: date, in: context)
        let backup = try FullBackup.decode(FullBackup.export(in: context))
        for _ in 0..<2 {
            let visible = LedgerProjection.entries(try context.fetch(FetchDescriptor<LedgerEntry>()))
            try LedgerStore.delete(XCTUnwrap(visible.first), in: context)
            XCTAssertEqual(try FullBackup.restore(backup, in: context).transactions, 1)
            XCTAssertEqual(try FullBackup.restore(backup, in: context).transactions, 0)
            let restored = LedgerProjection.entries(try context.fetch(FetchDescriptor<LedgerEntry>()))
            XCTAssertEqual(restored.count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ImportActivity>()).first?.entryID, restored.first?.id)
        }
    }

    func testRestoreKeepsNewerUserEdits() throws {
        let container = try store(); let context = container.mainContext
        _ = try LedgerStore.importMessage(sms, receivedAt: date, in: context)
        try LedgerStore.setBudget(categoryID: "food", monthKey: "2026-10", amountPaise: 10000, in: context)
        let backup = try FullBackup.decode(FullBackup.export(in: context))
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEntry>()).first)
        entry.categoryID = "shopping"; entry.notes = "Keep this edit"
        let category = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.id == "food" })
        category.name = "Keep this category"; category.updatedAt = .now
        try LedgerStore.setBudget(categoryID: "food", monthKey: "2026-10", amountPaise: 20000, in: context)
        _ = try FullBackup.restore(backup, in: context)
        XCTAssertEqual(entry.categoryID, "shopping"); XCTAssertEqual(entry.notes, "Keep this edit")
        XCTAssertEqual(category.name, "Keep this category")
        XCTAssertEqual(try context.fetch(FetchDescriptor<MonthlyBudget>()).first?.amountPaise, 20000)
    }

    func testInvalidBackupIsRejectedBeforeAnyMutation() throws {
        let container = try store(); let context = container.mainContext
        var backup = try FullBackup.decode(FullBackup.export(in: context))
        backup.categories.append(backup.categories[0])
        XCTAssertThrowsError(try FullBackup.restore(backup, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerCategory>()), CategoryTemplate.defaults.count)
        XCTAssertThrowsError(try FullBackup.decode(Data("{\"format\":\"PocketLedgerBackup\",\"version\":999}".utf8)))
        XCTAssertThrowsError(try FullBackup.decode(Data("not a backup".utf8)))
    }

    func testDateRangesIncludeWholeEndDayAndMonthBoundaries() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        func date(_ day: Int, hour: Int = 0, month: Int = 10) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        XCTAssertTrue(LedgerDateScope.custom.contains(date(25, hour: 23), month: date(1), start: date(24, hour: 12), end: date(25), calendar: calendar))
        XCTAssertFalse(LedgerDateScope.custom.contains(date(26), month: date(1), start: date(24), end: date(25), calendar: calendar))
        XCTAssertTrue(LedgerDateScope.month.contains(date(31, hour: 23), month: date(1), start: date(1), end: date(1), calendar: calendar))
        XCTAssertFalse(LedgerDateScope.month.contains(date(1, month: 11), month: date(1), start: date(1), end: date(1), calendar: calendar))
        XCTAssertTrue(LedgerDateScope.allTime.contains(.distantPast, month: date(1), start: date(1), end: date(1)))
    }

    func testPaymentGroupsSeparateBanksMethodsAndSuffixes() throws {
        let entries = [
            LedgerEntry(amountPaise: 10000, merchant: "A", date: date, payment: .card, bank: .icici, accountSuffix: "9003"),
            LedgerEntry(amountPaise: 2000, merchant: "A", date: date, kind: .refund, payment: .card, bank: .icici, accountSuffix: "9003"),
            LedgerEntry(amountPaise: 10000, merchant: "B", date: date, payment: .card, bank: .hdfc, accountSuffix: "9003"),
            LedgerEntry(amountPaise: 10000, merchant: "C", date: date, payment: .upi, bank: .icici, accountSuffix: "9003")
        ]
        let key = PaymentGroup.key(for: entries[0])
        let groups = PaymentGroup.groups(entries: entries, accounts: [PaymentAccount(key: key, nickname: "My card")])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first { $0.id == key }?.name, "My card")
        XCTAssertEqual(LedgerProjection.netSpending(entries.filter { PaymentGroup.key(for: $0) == key }), 8000)
    }

    func testExistingV2StoreMigratesWithoutLosingDataAndReopens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        try autoreleasepool {
            let schema = Schema(versionedSchema: LedgerSchemaV2.self)
            let config = ModelConfiguration("PocketLedger", schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            old.mainContext.insert(LedgerEntry(id: "existing", amountPaise: 50000, merchant: "Existing transaction", date: date))
            old.mainContext.insert(MonthlyBudget(categoryID: "food", monthKey: "2026-10", amountPaise: 300000))
            try old.mainContext.save()
        }
        try autoreleasepool {
            let migrated = try LedgerStore.makeContainer(url: url)
            XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<LedgerEntry>()).first?.id, "existing")
            XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<MonthlyBudget>()), 1)
            try LedgerStore.seedCategories(in: migrated.mainContext)
            _ = try LedgerStore.importMessage(sms, origin: "shortcut", in: migrated.mainContext)
            try LedgerStore.setNickname("Migrated card", for: "card|ICICI|9003", in: migrated.mainContext)
        }
        let reopened = try LedgerStore.makeContainer(url: url)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<LedgerEntry>()), 2)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<ImportActivity>()), 1)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<PaymentAccount>()), 1)
    }
}
