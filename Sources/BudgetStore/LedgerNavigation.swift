import Foundation
#if canImport(BudgetCore)
import BudgetCore
#endif

public enum LedgerDateScope: String, CaseIterable, Identifiable {
    case month = "Month", allTime = "All time", custom = "Date range"
    public var id: String { rawValue }

    public func contains(_ date: Date, month: Date, start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .allTime: return true
        case .month: return calendar.isDate(date, equalTo: month, toGranularity: .month)
        case .custom:
            let lower = calendar.startOfDay(for: start)
            guard let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) else { return false }
            return date >= lower && date < upper
        }
    }
}

public struct PaymentGroup: Identifiable {
    public let id: String
    public let method: PaymentMethod
    public let bank: Bank
    public let suffix: String
    public let nickname: String
    public var defaultName: String {
        let bankName = bank == .unknown ? "" : bank.rawValue + " "
        let ending = suffix.isEmpty ? "" : " •" + suffix
        return bankName + method.label + ending
    }
    public var name: String { nickname.isEmpty ? defaultName : nickname }
    public var symbol: String { method == .card ? "creditcard" : method == .upi ? "qrcode" : "banknote" }

    public static func key(method: PaymentMethod, bank: Bank, suffix: String) -> String {
        [method.rawValue, bank.rawValue, suffix].joined(separator: "|")
    }

    @MainActor public static func key(for entry: LedgerEntry) -> String {
        key(method: entry.payment, bank: entry.bank, suffix: entry.accountSuffix)
    }

    @MainActor public static func groups(entries: [LedgerEntry], accounts: [PaymentAccount]) -> [PaymentGroup] {
        let names = Dictionary(uniqueKeysWithValues: LedgerProjection.accounts(accounts).map { ($0.key, $0.nickname) })
        return Dictionary(grouping: entries, by: { key(for: $0) }).compactMap { key, records in
            guard let entry = records.first else { return nil }
            return PaymentGroup(id: key, method: entry.payment, bank: entry.bank, suffix: entry.accountSuffix, nickname: names[key] ?? "")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
