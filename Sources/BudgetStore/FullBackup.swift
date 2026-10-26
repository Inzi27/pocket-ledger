import Foundation
import SwiftData
import CryptoKit
#if canImport(BudgetCore)
import BudgetCore
#endif

public struct LedgerBackup: Codable {
    public var format = "PocketLedgerBackup"
    public var version = 1
    public var createdAt = Date.now
    public var entries: [Entry]
    public var categories: [Category]
    public var rules: [Rule]
    public var budgets: [Budget]
    public var accounts: [Account]
    public var activities: [Activity]

    public struct Entry: Codable {
        public var id: String; public var amount: Int64; public var merchant: String; public var date: Date
        public var kind: String; public var payment: String; public var bank: String; public var suffix: String
        public var categoryID: String; public var notes: String; public var source: String; public var reviewReason: String
        public var createdAt: Date; public var updatedAt: Date
    }
    public struct Category: Codable {
        public var id: String; public var name: String; public var symbol: String; public var tint: String
        public var archived: Bool; public var order: Int; public var updatedAt: Date
    }
    public struct Rule: Codable { public var merchant: String; public var categoryID: String; public var updatedAt: Date }
    public struct Budget: Codable { public var id: String; public var categoryID: String; public var month: String; public var amount: Int64; public var updatedAt: Date }
    public struct Account: Codable { public var key: String; public var nickname: String; public var updatedAt: Date }
    public struct Activity: Codable { public var id: String; public var date: Date; public var origin: String; public var status: String; public var detail: String; public var entryID: String }
}

public enum FullBackupError: Error, LocalizedError {
    case invalid, unsupported, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalid: return "This is not a valid Pocket Ledger backup. No data was changed."
        case .unsupported: return "This backup needs a newer version of Pocket Ledger."
        case .tooLarge: return "Choose a backup smaller than 50 MB."
        }
    }
}

public struct BackupRestoreResult {
    public var transactions = 0
    public var skippedTransactions = 0
    public var categories = 0
    public var rules = 0
    public var budgets = 0
    public var accounts = 0
    public var activities = 0
    public var message: String {
        "Restored \(transactions) transactions, \(categories) categories, \(rules) rules, \(budgets) budgets, \(accounts) payment names, and \(activities) import events. Kept \(skippedTransactions) existing transactions."
    }
}

@MainActor public enum FullBackup {
    public static func export(in context: ModelContext) throws -> Data {
        let backup = LedgerBackup(
            entries: LedgerProjection.entries(try context.fetch(FetchDescriptor<LedgerEntry>())).map {
                .init(id: $0.id, amount: $0.amountPaise, merchant: $0.merchant, date: $0.date, kind: $0.kindRaw,
                      payment: $0.paymentRaw, bank: $0.bankRaw, suffix: $0.accountSuffix, categoryID: $0.categoryID,
                      notes: $0.notes, source: $0.source, reviewReason: $0.reviewReason, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            categories: LedgerProjection.categories(try context.fetch(FetchDescriptor<LedgerCategory>())).map {
                .init(id: $0.id, name: $0.name, symbol: $0.symbol, tint: $0.tint, archived: $0.isArchived, order: $0.order, updatedAt: $0.updatedAt)
            },
            rules: LedgerProjection.rules(try context.fetch(FetchDescriptor<MerchantRule>())).map {
                .init(merchant: $0.merchantKey, categoryID: $0.categoryID, updatedAt: $0.updatedAt)
            },
            budgets: LedgerProjection.budgets(try context.fetch(FetchDescriptor<MonthlyBudget>())).map {
                .init(id: $0.id, categoryID: $0.categoryID, month: $0.monthKey, amount: $0.amountPaise, updatedAt: $0.updatedAt)
            },
            accounts: LedgerProjection.accounts(try context.fetch(FetchDescriptor<PaymentAccount>())).map {
                .init(key: $0.key, nickname: $0.nickname, updatedAt: $0.updatedAt)
            },
            activities: LedgerProjection.activities(try context.fetch(FetchDescriptor<ImportActivity>())).map {
                .init(id: $0.id, date: $0.date, origin: $0.origin, status: $0.status, detail: $0.detail, entryID: $0.entryID)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> LedgerBackup {
        guard data.count <= 50_000_000 else { throw FullBackupError.tooLarge }
        // Read the envelope first so future versions can explain their incompatibility.
        struct Envelope: Decodable { let format: String; let version: Int }
        guard let header = try? JSONDecoder().decode(Envelope.self, from: data), header.format == "PocketLedgerBackup" else { throw FullBackupError.invalid }
        guard header.version == 1 else { throw FullBackupError.unsupported }
        guard let backup = try? JSONDecoder().decode(LedgerBackup.self, from: data) else { throw FullBackupError.invalid }
        try validate(backup)
        return backup
    }

    private static func validate(_ backup: LedgerBackup) throws {
        func unique(_ values: [String]) -> Bool { values.allSatisfy { !$0.isEmpty } && Set(values).count == values.count }
        let categories = Set(backup.categories.map(\.id))
        guard backup.format == "PocketLedgerBackup", backup.version == 1,
              unique(backup.entries.map(\.id)), unique(backup.categories.map(\.id)),
              unique(backup.rules.map(\.merchant)), unique(backup.budgets.map { $0.month + "|" + $0.categoryID }),
              unique(backup.accounts.map(\.key)), unique(backup.activities.map(\.id)),
              backup.entries.allSatisfy({ $0.amount > 0 && $0.amount <= 100_000_000_000 && !$0.merchant.isEmpty && categories.contains($0.categoryID)
                  && TransactionKind(rawValue: $0.kind) != nil && PaymentMethod(rawValue: $0.payment) != nil && Bank(rawValue: $0.bank) != nil }),
              backup.categories.allSatisfy({ !$0.name.isEmpty }),
              backup.rules.allSatisfy({ categories.contains($0.categoryID) }),
              backup.budgets.allSatisfy({ $0.amount > 0 && $0.amount <= 100_000_000_000 && categories.contains($0.categoryID)
                  && $0.month.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil }),
              backup.accounts.allSatisfy({ $0.nickname.count <= 40 }),
              backup.activities.allSatisfy({ ["saved", "duplicate", "ignored", "unrecognized", "failed"].contains($0.status) })
        else { throw FullBackupError.invalid }
    }

    public static func restore(_ backup: LedgerBackup, in context: ModelContext) throws -> BackupRestoreResult {
        try validate(backup)
        // Fetch before mutating. Save once so a failure rolls the entire restore back.
        var entries = Dictionary(grouping: try context.fetch(FetchDescriptor<LedgerEntry>()), by: \.id)
        let categories = LedgerProjection.categories(try context.fetch(FetchDescriptor<LedgerCategory>()))
        let rules = try context.fetch(FetchDescriptor<MerchantRule>())
        let budgets = try context.fetch(FetchDescriptor<MonthlyBudget>())
        let accounts = LedgerProjection.accounts(try context.fetch(FetchDescriptor<PaymentAccount>()))
        let existingActivities = try context.fetch(FetchDescriptor<ImportActivity>())
        let activityIDs = Set(existingActivities.map(\.id))
        var result = BackupRestoreResult()
        var entryMapping: [String: String] = [:]
        func recoveredID(_ original: String) -> String {
            var id = original
            while let group = entries[id], group.contains(where: \.isDeleted) {
                id = "csv-restore:" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
            }
            return id
        }
        for item in backup.categories {
            // Fresh installations seed defaults at epoch; restore backed-up customizations over those defaults.
            if let existing = categories.first(where: { $0.id == item.id }), existing.updatedAt > Date(timeIntervalSince1970: 0) { continue }
            let record = categories.first { $0.id == item.id } ?? LedgerCategory(id: item.id, name: item.name)
            if record.modelContext == nil { context.insert(record) }
            record.name = item.name; record.symbol = item.symbol; record.tint = item.tint; record.order = item.order
            record.isArchived = item.archived; record.updatedAt = .now
            result.categories += 1
        }
        for item in backup.entries {
            // Match CSV recovery IDs, and support restoring the same backup after a later deletion too.
            let id = recoveredID(item.id)
            entryMapping[item.id] = id
            if entries[id] != nil { result.skippedTransactions += 1; continue }
            let record = LedgerEntry(id: id, amountPaise: item.amount, merchant: item.merchant, date: item.date,
                                     kind: TransactionKind(rawValue: item.kind)!, payment: PaymentMethod(rawValue: item.payment)!,
                                     bank: Bank(rawValue: item.bank)!, accountSuffix: item.suffix, categoryID: item.categoryID,
                                     notes: item.notes, source: item.source, reviewReason: item.reviewReason)
            record.createdAt = item.createdAt; record.updatedAt = item.updatedAt
            context.insert(record); entries[id] = [record]; result.transactions += 1
        }
        let activeRuleKeys = Set(LedgerProjection.rules(rules).map(\.merchantKey))
        for item in backup.rules where !activeRuleKeys.contains(item.merchant) {
            let matches = rules.filter { $0.merchantKey == item.merchant }
            if matches.isEmpty { context.insert(MerchantRule(merchantKey: item.merchant, categoryID: item.categoryID)) }
            for record in matches { record.categoryID = item.categoryID; record.isDeleted = false; record.updatedAt = .now }
            result.rules += 1
        }
        let activeBudgetKeys = Set(LedgerProjection.budgets(budgets).map(\.budgetKey))
        for item in backup.budgets where !activeBudgetKeys.contains(item.month + "|" + item.categoryID) {
            let matches = budgets.filter { $0.monthKey == item.month && $0.categoryID == item.categoryID }
            if matches.isEmpty {
                let record = MonthlyBudget(categoryID: item.categoryID, monthKey: item.month, amountPaise: item.amount)
                record.id = item.id; context.insert(record)
            }
            for record in matches { record.amountPaise = item.amount; record.isDeleted = false; record.updatedAt = .now }
            result.budgets += 1
        }
        let accountKeys = Set(accounts.map(\.key))
        for item in backup.accounts where !accountKeys.contains(item.key) {
            context.insert(PaymentAccount(key: item.key, nickname: item.nickname)); result.accounts += 1
        }
        for activity in existingActivities where !activity.entryID.isEmpty {
            let recovered = recoveredID(activity.entryID)
            if entries[recovered] != nil { activity.entryID = recovered }
        }
        for item in backup.activities where !activityIDs.contains(item.id) {
            let record = ImportActivity(date: item.date, origin: item.origin, status: item.status, detail: item.detail,
                                        entryID: entryMapping[item.entryID] ?? recoveredID(item.entryID))
            record.id = item.id; context.insert(record); result.activities += 1
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return result
    }
}
