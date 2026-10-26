import XCTest
import SwiftData
import BudgetCore
@testable import BudgetStore

@MainActor final class CSVBackupTests: XCTestCase {
    private func makeStore() throws -> ModelContainer {
        let container = try LedgerStore.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        try LedgerStore.seedCategories(in: container.mainContext)
        return container
    }

    func testExportDeleteRestoreAndRepeatedImport() throws {
        let container = try makeStore()
        let context = container.mainContext
        let date = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        let category = LedgerCategory(id: "custom", name: "Personal", symbol: "gift.fill", tint: "purple")
        context.insert(category)
        let originals = [
            LedgerEntry(id: "manual-one", amountPaise: 11000, merchant: "Sample shop", date: date, categoryID: "custom"),
            LedgerEntry(id: "sms:sample", amountPaise: 20900, merchant: "Cafe, \"Central\"", date: date,
                        payment: .card, bank: .icici, accountSuffix: "9003", categoryID: "food",
                        notes: "First line\r\nSecond line", source: "sms", reviewReason: "Check category.")
        ]
        for entry in originals { context.insert(entry) }
        try context.save()
        let csv = LedgerStore.csv(entries: originals, categories: try context.fetch(FetchDescriptor<LedgerCategory>()))
        XCTAssertTrue(csv.contains("\r\n"))

        for entry in originals { entry.markDeleted() }
        try context.save()
        let preview = try CSVBackup.preview(csv, existingEntries: context.fetch(FetchDescriptor<LedgerEntry>()),
                                            categories: context.fetch(FetchDescriptor<LedgerCategory>()))
        XCTAssertEqual(preview.transactions.count, 2)
        XCTAssertEqual(preview.restoredDeletedCount, 2)
        XCTAssertEqual(preview.invalidCount, 0)
        XCTAssertEqual(try CSVBackup.importTransactions(preview, in: context).importedCount, 2)

        let fresh = ModelContext(container)
        let visible = LedgerProjection.entries(try fresh.fetch(FetchDescriptor<LedgerEntry>()))
        XCTAssertEqual(visible.count, 2)
        XCTAssertEqual(visible.map(\.amountPaise).sorted(), [11000, 20900])
        let restoredCard = try XCTUnwrap(visible.first { $0.accountSuffix == "9003" })
        XCTAssertEqual(restoredCard.merchant, "Cafe, \"Central\"")
        XCTAssertEqual(restoredCard.notes, "First line\r\nSecond line")
        XCTAssertTrue(restoredCard.needsReview)
        let repeated = try CSVBackup.preview(csv, existingEntries: fresh.fetch(FetchDescriptor<LedgerEntry>()),
                                             categories: fresh.fetch(FetchDescriptor<LedgerCategory>()))
        XCTAssertTrue(repeated.transactions.isEmpty)
        XCTAssertEqual(repeated.duplicateCount, 2)
    }

    func testCSVLineEndingVariantsAndLegacyColumns() throws {
        let header = "Date,Merchant,Amount INR,Type,Payment,Bank,Account suffix,Category,Notes,Source,Needs review"
        let row = "2026-10-25T12:00:00Z,Sample shop,110.00,Expense,UPI,Other,,Uncategorized,,manual,No"
        for separator in ["\r\n", "\n", "\r"] {
            let preview = try CSVBackup.preview(header + separator + row + separator, existingEntries: [], categories: [])
            XCTAssertEqual(preview.transactions.count, 1, "Line ending: \(separator.debugDescription)")
            XCTAssertEqual(preview.invalidCount, 0)
        }
    }
}
