import Foundation
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif

// CloudKit requires defaults/optionals and does not support unique constraints.
// Stable logical IDs and the projections below reconcile records created offline.
@Model public final class LedgerEntry {
    public var recordID: UUID = UUID()
    public var id: String = UUID().uuidString
    public var amountPaise: Int64 = 0
    public var merchant: String = ""
    public var date: Date = Date.now
    public var kindRaw: String = "expense"
    public var paymentRaw: String = "other"
    public var bankRaw: String = "Other"
    public var accountSuffix: String = ""
    public var categoryID: String = "other"
    public var notes: String = ""
    public var source: String = "manual"
    public var reviewReason: String = ""
    public var isDeleted: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(id: String = UUID().uuidString, amountPaise: Int64, merchant: String, date: Date,
                kind: TransactionKind = .expense, payment: PaymentMethod = .other,
                bank: Bank = .unknown, accountSuffix: String = "", categoryID: String = "other",
                notes: String = "", source: String = "manual", reviewReason: String = "") {
        self.id = id; self.amountPaise = amountPaise; self.merchant = merchant; self.date = date
        self.kindRaw = kind.rawValue; self.paymentRaw = payment.rawValue; self.bankRaw = bank.rawValue
        self.accountSuffix = accountSuffix; self.categoryID = categoryID; self.notes = notes
        self.source = source; self.reviewReason = reviewReason
    }
    public var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .expense }
    public var payment: PaymentMethod { PaymentMethod(rawValue: paymentRaw) ?? .other }
    public var bank: Bank { Bank(rawValue: bankRaw) ?? .unknown }
    public var needsReview: Bool { !reviewReason.isEmpty }
    public var isTombstone: Bool { isDeleted || source == "deleted" }
    public func markDeleted() {
        isDeleted = true; updatedAt = .now
        merchant = ""; notes = ""; accountSuffix = ""; amountPaise = 0; reviewReason = ""
        bankRaw = Bank.unknown.rawValue; paymentRaw = PaymentMethod.other.rawValue
        kindRaw = TransactionKind.expense.rawValue; categoryID = "other"; source = "deleted"
        date = Date(timeIntervalSince1970: 0); createdAt = Date(timeIntervalSince1970: 0)
    }
}

@Model public final class LedgerCategory {
    public var recordID: UUID = UUID()
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var symbol: String = "tag.fill"
    public var tint: String = "teal"
    public var isArchived: Bool = false
    public var order: Int = 0
    public var updatedAt: Date = Date.now
    public init(id: String = UUID().uuidString, name: String, symbol: String = "tag.fill", tint: String = "teal", order: Int = 0) {
        self.id = id; self.name = name; self.symbol = symbol; self.tint = tint; self.order = order
    }
}

@Model public final class MerchantRule {
    public var recordID: UUID = UUID()
    public var merchantKey: String = ""
    public var categoryID: String = "other"
    public var updatedAt: Date = Date.now
    public var isDeleted: Bool = false
    public init(merchantKey: String, categoryID: String) {
        self.merchantKey = merchantKey; self.categoryID = categoryID
    }
}

@Model public final class MonthlyBudget {
    public var recordID: UUID = UUID()
    public var id: String = UUID().uuidString
    public var categoryID: String = "other"
    public var monthKey: String = ""
    public var amountPaise: Int64 = 0
    public var isDeleted: Bool = false
    public var updatedAt: Date = Date.now
    public var budgetKey: String { "\(monthKey)|\(categoryID)" }
    public init(categoryID: String, monthKey: String, amountPaise: Int64) {
        self.categoryID = categoryID; self.monthKey = monthKey; self.amountPaise = amountPaise
    }
}

public enum LedgerSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [LedgerEntry.self, LedgerCategory.self, MerchantRule.self] }
}

public enum LedgerMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self, LedgerSchemaV2.self, LedgerSchemaV3.self] }
    public static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: LedgerSchemaV1.self, toVersion: LedgerSchemaV2.self),
         MigrationStage.lightweight(fromVersion: LedgerSchemaV2.self, toVersion: LedgerSchemaV3.self)]
    }
}

public enum LedgerSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    public static var models: [any PersistentModel.Type] { [LedgerEntry.self, LedgerCategory.self, MerchantRule.self, MonthlyBudget.self] }
}

// New entities leave the existing transaction schema unchanged during migration.
@Model public final class ImportActivity {
    public var id: String = UUID().uuidString
    public var date: Date = Date.now
    public var origin: String = "paste"
    public var status: String = "saved"
    public var detail: String = ""
    public var entryID: String = ""
    public init(date: Date = .now, origin: String, status: String, detail: String, entryID: String = "") {
        self.date = date; self.origin = origin; self.status = status; self.detail = detail; self.entryID = entryID
    }
}

@Model public final class PaymentAccount {
    public var recordID: UUID = UUID()
    public var key: String = ""
    public var nickname: String = ""
    public var updatedAt: Date = Date.now
    public init(key: String, nickname: String) { self.key = key; self.nickname = nickname }
}

public enum LedgerSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [LedgerEntry.self, LedgerCategory.self, MerchantRule.self, MonthlyBudget.self, ImportActivity.self, PaymentAccount.self]
    }
}

@MainActor public enum LedgerProjection {
    public static func accounts(_ records: [PaymentAccount]) -> [PaymentAccount] {
        Dictionary(grouping: records, by: \.key).values.compactMap { group in
            group.sorted {
                $0.updatedAt == $1.updatedAt ? $0.recordID.uuidString < $1.recordID.uuidString : $0.updatedAt > $1.updatedAt
            }.first
        }.sorted { $0.key < $1.key }
    }
    public static func activities(_ records: [ImportActivity]) -> [ImportActivity] {
        Dictionary(grouping: records, by: \.id).values.compactMap { $0.max { $0.date < $1.date } }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    public static func budgets(_ records: [MonthlyBudget]) -> [MonthlyBudget] {
        Dictionary(grouping: records, by: \.budgetKey).values.compactMap { group in
            let latest = group.sorted {
                $0.updatedAt == $1.updatedAt ? $0.recordID.uuidString < $1.recordID.uuidString : $0.updatedAt > $1.updatedAt
            }.first
            return latest?.isDeleted == false && (latest?.amountPaise ?? 0) > 0 ? latest : nil
        }
    }
    /// A deletion wins over an offline duplicate so deleted imports cannot reappear.
    public static func entries(_ records: [LedgerEntry]) -> [LedgerEntry] {
        Dictionary(grouping: records, by: \.id).values.compactMap { group in
            guard !group.contains(where: \.isTombstone) else { return nil }
            return group.sorted {
                $0.updatedAt == $1.updatedAt ? $0.recordID.uuidString < $1.recordID.uuidString : $0.updatedAt > $1.updatedAt
            }.first
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    public static func categories(_ records: [LedgerCategory]) -> [LedgerCategory] {
        var latestByID: [String: LedgerCategory] = [:]
        for record in records {
            guard let current = latestByID[record.id] else {
                latestByID[record.id] = record
                continue
            }

            let recordComesFirst: Bool
            if record.updatedAt == current.updatedAt {
                recordComesFirst = record.recordID.uuidString < current.recordID.uuidString
            } else {
                recordComesFirst = record.updatedAt > current.updatedAt
            }
            if recordComesFirst {
                latestByID[record.id] = record
            }
        }

        let latestCategories: [LedgerCategory] = Array(latestByID.values)
        return latestCategories.sorted { (left: LedgerCategory, right: LedgerCategory) in
            if left.order == right.order {
                return left.name < right.name
            }
            return left.order < right.order
        }
    }
    public static func rules(_ records: [MerchantRule]) -> [MerchantRule] {
        Dictionary(grouping: records, by: \.merchantKey).values.compactMap { group in
            let latest = group.sorted {
                $0.updatedAt == $1.updatedAt ? $0.recordID.uuidString < $1.recordID.uuidString : $0.updatedAt > $1.updatedAt
            }.first
            return latest?.isDeleted == false ? latest : nil
        }.sorted { $0.merchantKey < $1.merchantKey }
    }
    public static func netSpending(_ entries: [LedgerEntry]) -> Int64 {
        entries.reduce(0) { $0 + ($1.kind == .expense ? $1.amountPaise : $1.kind == .refund ? -$1.amountPaise : 0) }
    }
}
