import Foundation
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif

public enum ImportOutcome: Equatable, Sendable {
    case saved(needsReview: Bool), duplicate, ignored(String), unrecognized(String)
    public var message: String {
        switch self {
        case .saved(let review): return review ? "Saved. A few details need checking in Review." : "Transaction saved."
        case .duplicate: return "Already imported. No duplicate was added."
        case .ignored(let reason), .unrecognized(let reason): return reason
        }
    }
}

@MainActor public enum LedgerStore {
    public static func makeContainer(url: URL? = nil, cloudContainer: String? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LedgerSchemaV2.self)
        let database: ModelConfiguration.CloudKitDatabase = cloudContainer.map { .private($0) } ?? .none
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration("PocketLedger", schema: schema, url: url, cloudKitDatabase: database)
        } else {
            config = ModelConfiguration("PocketLedger", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: database)
        }
        return try ModelContainer(for: schema, migrationPlan: LedgerMigrationPlan.self, configurations: [config])
    }

    public static func seedCategories(in context: ModelContext) throws {
        let ids = Set(try context.fetch(FetchDescriptor<LedgerCategory>()).map(\.id))
        for (index, template) in CategoryTemplate.defaults.enumerated() where !ids.contains(template.id) {
            let category = LedgerCategory(id: template.id, name: template.name, symbol: template.symbol, tint: template.tint, order: index)
            category.updatedAt = Date(timeIntervalSince1970: 0)
            context.insert(category)
        }
        try context.save()
    }

    public static func monthKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public static func setBudget(categoryID: String, monthKey: String, amountPaise: Int64, in context: ModelContext) throws {
        guard !categoryID.isEmpty, monthKey.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil, amountPaise >= 0 else {
            throw NSError(domain: "PocketLedger.Budget", code: 1, userInfo: [NSLocalizedDescriptionKey: "That monthly budget is invalid."])
        }
        let matches = try context.fetch(FetchDescriptor<MonthlyBudget>(predicate: #Predicate { $0.categoryID == categoryID && $0.monthKey == monthKey }))
        if matches.isEmpty {
            if amountPaise > 0 { context.insert(MonthlyBudget(categoryID: categoryID, monthKey: monthKey, amountPaise: amountPaise)) }
        } else {
            for budget in matches {
                budget.amountPaise = amountPaise
                budget.isDeleted = amountPaise == 0
                budget.updatedAt = .now
            }
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    public static func importMessage(_ message: String, sender: String = "", receivedAt: Date = .now, in context: ModelContext) throws -> ImportOutcome {
        switch MessageParser().parse(message, sender: sender, receivedAt: receivedAt) {
        case .ignored(let reason): return .ignored(reason)
        case .unrecognized(let reason): return .unrecognized(reason)
        case .transaction(let parsed):
            let id = "sms:" + parsed.fingerprint
            let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id })

            // 1. Handle duplication and "Auto-Repair" category
            let existingRecords = try context.fetch(descriptor)
            let isDuplicate = !existingRecords.isEmpty

            let categories = LedgerProjection.categories(try context.fetch(FetchDescriptor<LedgerCategory>()))
            let rules = LedgerProjection.rules(try context.fetch(FetchDescriptor<MerchantRule>()))
            let merchantKey = MerchantCategory.normalized(parsed.merchant)

            // 2. Determine the best category
            var suggested = rules.first(where: { $0.merchantKey == merchantKey })?.categoryID
            if suggested == nil {
                suggested = MerchantCategory.suggested(for: parsed.merchant)
            }
            if suggested == nil || suggested == "other" {
                suggested = MerchantCategory.suggested(for: message)
            }

            let categoryID = categories.contains(where: { $0.id == suggested && !$0.isArchived }) ? (suggested ?? "other") : "other"

            if isDuplicate {
                // If it's a duplicate but we found a better category, update it automatically
                if let existing = existingRecords.first, !existing.isDeleted && existing.categoryID != categoryID {
                    existing.categoryID = categoryID
                    existing.updatedAt = .now
                    try context.save()
                }
                return .duplicate
            }

            let entry = LedgerEntry(id: id, amountPaise: parsed.amountPaise, merchant: parsed.merchant, date: parsed.date,
                                    kind: parsed.kind, payment: parsed.payment, bank: parsed.bank,
                                    accountSuffix: parsed.accountSuffix, categoryID: categoryID, source: "sms",
                                    reviewReason: parsed.reviewReason)
            context.insert(entry)
            do { try context.save() } catch { context.rollback(); throw error }
            return .saved(needsReview: parsed.needsReview)
        }
    }

    public static func remember(merchant: String, categoryID: String, in context: ModelContext) throws {
        let key = MerchantCategory.normalized(merchant)
        guard !key.isEmpty, key != "unknown merchant" else { return }
        let matches = try context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.merchantKey == key }))
        if matches.isEmpty { context.insert(MerchantRule(merchantKey: key, categoryID: categoryID)) }
        for rule in matches { rule.categoryID = categoryID; rule.isDeleted = false; rule.updatedAt = .now }
        try context.save()
    }

    public static func delete(_ entry: LedgerEntry, in context: ModelContext) throws {
        let id = entry.id
        let matches = try context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id }))
        for record in matches {
            record.markDeleted()
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    public static func csv(entries: [LedgerEntry], categories: [LedgerCategory]) -> String {
        let projectedCategories = LedgerProjection.categories(categories)
        let names = Dictionary(uniqueKeysWithValues: projectedCategories.map { ($0.id, $0.name) })
        let symbols = Dictionary(uniqueKeysWithValues: projectedCategories.map { ($0.id, $0.symbol) })
        let tints = Dictionary(uniqueKeysWithValues: projectedCategories.map { ($0.id, $0.tint) })
        let formatter = ISO8601DateFormatter()
        var rows = ["Date,Merchant,Amount INR,Type,Payment,Bank,Account suffix,Category,Notes,Source,Needs review,Ledger ID,Category ID,Category symbol,Category tint"]
        for entry in LedgerProjection.entries(entries) {
            rows.append([formatter.string(from: entry.date), entry.merchant, Money.input(entry.amountPaise), entry.kind.label,
                         entry.payment.label, entry.bank.rawValue, entry.accountSuffix, names[entry.categoryID] ?? "Uncategorized",
                         entry.notes, entry.source, entry.needsReview ? "Yes" : "No", entry.id, entry.categoryID,
                         symbols[entry.categoryID] ?? "tag.fill", tints[entry.categoryID] ?? "teal"].map(csvCell).joined(separator: ","))
        }
        return rows.joined(separator: "\r\n")
    }
    private static func csvCell(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: value.hasPrefix) || ["=", "+", "-", "@"].contains(where: trimmed.hasPrefix) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func isBadMerchant(_ merchant: String) -> Bool {
        let value = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.caseInsensitiveCompare("Unknown merchant") == .orderedSame
            || value.range(of: #"^\+?[0-9 ()-]{7,}$"#, options: .regularExpression) != nil
    }
}
