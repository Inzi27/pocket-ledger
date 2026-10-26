import XCTest
import SwiftData
import BudgetCore
@testable import BudgetStore

@MainActor final class LedgerStoreTests: XCTestCase {
    let sms = "INR 1250.50 spent on HDFC Bank Credit Card XX1234 at AMAZON on 24-10-2026."
    let received = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
    func makeStore() throws -> ModelContainer {
        let container = try LedgerStore.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        try LedgerStore.seedCategories(in: container.mainContext)
        return container
    }
    func testImportPersistsAndDeduplicates() throws {
        let container = try makeStore(); let context = container.mainContext
        XCTAssertEqual(try LedgerStore.importMessage(sms, receivedAt: received, in: context), .saved(needsReview: false))
        XCTAssertEqual(try LedgerStore.importMessage(sms, receivedAt: received, in: context), .duplicate)
        let fresh = ModelContext(container)
        let records = try fresh.fetch(FetchDescriptor<LedgerEntry>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].categoryID, "shopping")
        XCTAssertEqual(records[0].amountPaise, 125050)
    }
    func testRepeatedImportRepairsPreviousBlockPhoneAsMerchant() throws {
        let container = try makeStore(); let context = container.mainContext
        let message = "INR 209.00 spent using ICICI Bank Card XX9003 on 25-Oct-26 on RSP*SWIGGY PVT . Avl Limit: INR 9,76,331.63. If not you, call 1800 2662/SMS BLOCK 9003 to 9215676766"
        guard case .transaction(let parsed) = MessageParser().parse(message, receivedAt: received) else {
            return XCTFail("Expected the bank message to parse")
        }
        let legacy = LedgerEntry(id: "sms:" + parsed.fingerprint, amountPaise: 20900, merchant: "9215676766",
                                 date: parsed.date, payment: .card, bank: .icici, accountSuffix: "9003", source: "sms")
        context.insert(legacy); try context.save()
        XCTAssertEqual(try LedgerStore.importMessage(message, receivedAt: received, in: context), .saved(needsReview: false))
        XCTAssertEqual(legacy.merchant, "RSP*SWIGGY PVT")
        XCTAssertEqual(legacy.categoryID, "food")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 1)
    }
    func testDeletedImportCannotReturn() throws {
        let container = try makeStore(); let context = container.mainContext
        _ = try LedgerStore.importMessage(sms, receivedAt: received, in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerEntry>()).first)
        try LedgerStore.delete(entry, in: context)
        XCTAssertEqual(try LedgerStore.importMessage(sms, receivedAt: received, in: context), .duplicate)
        XCTAssertTrue(LedgerProjection.entries(try context.fetch(FetchDescriptor<LedgerEntry>())).isEmpty)
        XCTAssertEqual(entry.merchant, "")
    }
    func testSeedIsIdempotentAndKeepsEdits() throws {
        let container = try makeStore(); let context = container.mainContext
        let category = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.id == "food" })
        category.name = "Eating out"; category.updatedAt = .now
        try context.save()
        try LedgerStore.seedCategories(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerCategory>()), CategoryTemplate.defaults.count)
        XCTAssertEqual(category.name, "Eating out")
    }
    func testMerchantRuleOverridesSuggestion() throws {
        let container = try makeStore(); let context = container.mainContext
        try LedgerStore.remember(merchant: " AMAZON ", categoryID: "bills", in: context)
        _ = try LedgerStore.importMessage(sms, receivedAt: received, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEntry>()).first?.categoryID, "bills")
    }
    func testArchivedCategoryIsNotAssigned() throws {
        let container = try makeStore(); let context = container.mainContext
        let shopping = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.id == "shopping" })
        shopping.isArchived = true
        try context.save()
        _ = try LedgerStore.importMessage(sms, receivedAt: received, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerEntry>()).first?.categoryID, "other")
    }
    func testProjectionReconcilesOfflineDuplicatesAndDeletion() {
        let a = LedgerEntry(id: "same", amountPaise: 100, merchant: "Original", date: received)
        let b = LedgerEntry(id: "same", amountPaise: 200, merchant: "Edited", date: received)
        b.updatedAt = a.updatedAt.addingTimeInterval(10)
        XCTAssertEqual(LedgerProjection.entries([a, b]).count, 1)
        XCTAssertEqual(LedgerProjection.entries([a, b]).first?.amountPaise, 200)
        a.isDeleted = true
        XCTAssertTrue(LedgerProjection.entries([a, b]).isEmpty)
        a.isDeleted = false
        a.source = "deleted"
        XCTAssertTrue(LedgerProjection.entries([a, b]).isEmpty)
    }
    func testRefundAndTransferTotals() {
        let entries = [LedgerEntry(amountPaise: 10000, merchant: "Shop", date: received),
                       LedgerEntry(amountPaise: 2500, merchant: "Shop", date: received, kind: .refund),
                       LedgerEntry(amountPaise: 10000, merchant: "Bill", date: received, kind: .transfer),
                       LedgerEntry(amountPaise: 99999, merchant: "Salary", date: received, kind: .income)]
        XCTAssertEqual(LedgerProjection.netSpending(entries), 7500)
    }
    func testCSVEscapesAndProtectsFormulas() {
        let entry = LedgerEntry(amountPaise: 1050, merchant: "=HYPERLINK(\"bad\")", date: received, notes: "A, B\nC")
        let csv = LedgerStore.csv(entries: [entry], categories: [])
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"bad\"\")\""))
        XCTAssertTrue(csv.contains("\"10.50\""))
        XCTAssertTrue(csv.contains("\"A, B\nC\""))
    }
    func testIgnoredMessagesLeaveNoRecords() throws {
        let container = try makeStore(); let context = container.mainContext
        _ = try LedgerStore.importMessage("OTP 123456 for INR 500 HDFC card purchase", in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerEntry>()), 0)
    }
    func testStoreCanReopenFromDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        try autoreleasepool {
            let first = try LedgerStore.makeContainer(url: url)
            try LedgerStore.seedCategories(in: first.mainContext)
            _ = try LedgerStore.importMessage(sms, receivedAt: received, in: first.mainContext)
        }
        let second = try LedgerStore.makeContainer(url: url)
        XCTAssertEqual(try second.mainContext.fetch(FetchDescriptor<LedgerEntry>()).first?.amountPaise, 125050)
    }
}
