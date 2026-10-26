import Foundation
import CryptoKit
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif

public struct CSVImportedTransaction: Sendable {
    public let id: String
    public let date: Date
    public let amountPaise: Int64
    public let merchant: String
    public let kind: TransactionKind
    public let payment: PaymentMethod
    public let bank: Bank
    public let accountSuffix: String
    public let categoryID: String
    public let categoryName: String
    public let categorySymbol: String
    public let categoryTint: String
    public let notes: String
    public let source: String
    public let needsReview: Bool
}

public struct CSVImportPreview: Sendable {
    public let transactions: [CSVImportedTransaction]
    public let duplicateCount: Int
    public let invalidCount: Int
    public let restoredDeletedCount: Int
    public let examples: [String]
}

public struct CSVImportResult: Sendable {
    public let importedCount: Int
    public let duplicateCount: Int
}

public enum CSVBackupError: Error, LocalizedError {
    case empty, malformed, missingColumns, tooLarge
    public var errorDescription: String? {
        switch self {
        case .empty: return "The CSV file is empty."
        case .malformed: return "The CSV file has an unfinished quoted field."
        case .missingColumns: return "This file is missing required Pocket Ledger transaction columns."
        case .tooLarge: return "This CSV is too large to import. Choose a file smaller than 10 MB."
        }
    }
}

@MainActor public enum CSVBackup {
    private static let requiredColumns = ["date", "merchant", "amount inr", "type", "payment", "bank", "account suffix", "category", "notes", "needs review"]

    public static func preview(_ text: String, existingEntries: [LedgerEntry], categories: [LedgerCategory]) throws -> CSVImportPreview {
        let rows = try parseRows(text)
        guard let header = rows.first else { throw CSVBackupError.empty }
        let normalizedHeader = header.enumerated().reduce(into: [String: Int]()) { result, element in
            result[element.element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = element.offset
        }
        guard requiredColumns.allSatisfy({ normalizedHeader[$0] != nil }) else { throw CSVBackupError.missingColumns }

        let existingGroups = Dictionary(grouping: existingEntries, by: \.id)
        var seenIDs = Set(existingGroups.keys)
        let knownCategories = LedgerProjection.categories(categories)
        var valid: [CSVImportedTransaction] = []
        var duplicates = 0
        var invalid = 0
        var restoredDeleted = 0
        var examples: [String] = []

        for (rowNumber, row) in rows.dropFirst().enumerated() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            func cell(_ name: String) -> String {
                guard let index = normalizedHeader[name], row.indices.contains(index) else { return "" }
                return restoreFormulaSafeCell(row[index]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let date = parseDate(cell("date")),
                  let amount = Money.paise(from: cell("amount inr")),
                  let kind = TransactionKind(rawValue: cell("type").lowercased()),
                  let payment = PaymentMethod.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(cell("payment")) == .orderedSame || $0.label.caseInsensitiveCompare(cell("payment")) == .orderedSame }),
                  let bank = Bank.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(cell("bank")) == .orderedSame }),
                  !cell("merchant").isEmpty else {
                invalid += 1
                if examples.count < 5 { examples.append("Row \(rowNumber + 2): missing or invalid date, amount, type, payment, bank, or merchant.") }
                continue
            }

            let categoryName = cell("category").isEmpty ? "Uncategorized" : cell("category")
            let providedCategoryID = cell("category id")
            let categoryID = providedCategoryID.isEmpty
                ? (knownCategories.first { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame }?.id ?? generatedCategoryID(categoryName))
                : providedCategoryID
            let categoryTemplate = CategoryTemplate.defaults.first { $0.id == categoryID }
            let categorySymbol = cell("category symbol").isEmpty ? (categoryTemplate?.symbol ?? "tag.fill") : cell("category symbol")
            let categoryTint = cell("category tint").isEmpty ? (categoryTemplate?.tint ?? "teal") : cell("category tint")
            let providedID = cell("ledger id")
            if providedID.isEmpty && existingEntries.contains(where: { entry in
                !entry.isTombstone && abs(entry.date.timeIntervalSince(date)) < 1
                    && entry.amountPaise == amount && entry.merchant == cell("merchant")
                    && entry.kind == kind && entry.payment == payment && entry.bank == bank
                    && entry.accountSuffix == cell("account suffix") && entry.categoryID == categoryID
                    && entry.notes == cell("notes")
            }) {
                duplicates += 1
                continue
            }
            var stableID = providedID.isEmpty ? generatedEntryID(row) : providedID
            if let group = existingGroups[stableID] {
                guard group.contains(where: \.isTombstone) else { duplicates += 1; continue }
                stableID = "csv-restore:" + digest(stableID)
                guard seenIDs.insert(stableID).inserted else { duplicates += 1; continue }
                restoredDeleted += 1
            } else {
                guard seenIDs.insert(stableID).inserted else { duplicates += 1; continue }
            }
            let needsReview = ["yes", "true", "1"].contains(cell("needs review").lowercased())
            valid.append(CSVImportedTransaction(id: stableID, date: date, amountPaise: amount, merchant: cell("merchant"),
                                                kind: kind, payment: payment, bank: bank, accountSuffix: cell("account suffix"),
                                                categoryID: categoryID, categoryName: categoryName, categorySymbol: categorySymbol,
                                                categoryTint: categoryTint, notes: cell("notes"),
                                                source: cell("source").isEmpty ? "csv" : cell("source"), needsReview: needsReview))
        }
        return CSVImportPreview(transactions: valid, duplicateCount: duplicates, invalidCount: invalid,
                                restoredDeletedCount: restoredDeleted, examples: examples)
    }

    @discardableResult public static func importTransactions(_ preview: CSVImportPreview, in context: ModelContext) throws -> CSVImportResult {
        let allEntries = try context.fetch(FetchDescriptor<LedgerEntry>())
        var existingIDs = Set(allEntries.map(\.id))
        var categoryRecords = try context.fetch(FetchDescriptor<LedgerCategory>())
        var knownCategoryIDs = Set(LedgerProjection.categories(categoryRecords).map(\.id))
        var imported = 0
        var duplicates = preview.duplicateCount
        for item in preview.transactions {
            guard existingIDs.insert(item.id).inserted else { duplicates += 1; continue }
            if knownCategoryIDs.insert(item.categoryID).inserted {
                let category = LedgerCategory(id: item.categoryID, name: item.categoryName,
                                              symbol: item.categorySymbol, tint: item.categoryTint,
                                              order: categoryRecords.count)
                context.insert(category)
                categoryRecords.append(category)
            }
            let entry = LedgerEntry(id: item.id, amountPaise: item.amountPaise, merchant: item.merchant, date: item.date,
                                    kind: item.kind, payment: item.payment, bank: item.bank,
                                    accountSuffix: item.accountSuffix, categoryID: item.categoryID,
                                    notes: item.notes, source: item.source,
                                    reviewReason: item.needsReview ? "Restored from CSV; please confirm the transaction details." : "")
            context.insert(entry)
            imported += 1
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return CSVImportResult(importedCount: imported, duplicateCount: duplicates)
    }

    private static func parseDate(_ value: String) -> Date? {
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        standard.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return standard.date(from: value)
    }

    private static func generatedEntryID(_ row: [String]) -> String {
        "csv:" + digest(row.joined(separator: "\u{1f}"))
    }

    private static func generatedCategoryID(_ name: String) -> String {
        "csv-category:" + digest(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func restoreFormulaSafeCell(_ value: String) -> String {
        guard value.count > 1, value.first == "'", let next = value.dropFirst().first,
              ["=", "+", "-", "@", "\t", "\r"].contains(next) else { return value }
        return String(value.dropFirst())
    }

    private static func parseRows(_ text: String) throws -> [[String]] {
        let characters = Array(text.replacingOccurrences(of: "\u{feff}", with: ""))
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        cell.append("\""); index += 1
                    } else { quoted = false }
                } else { cell.append(character) }
            } else {
                switch character {
                case "\"" where cell.isEmpty: quoted = true
                case ",": row.append(cell); cell = ""
                // Swift treats CRLF as one extended grapheme cluster (Character).
                // Handle it explicitly, along with standalone LF and CR row endings.
                case "\r\n", "\n", "\r": row.append(cell); rows.append(row); row = []; cell = ""
                default: cell.append(character)
                }
            }
            index += 1
        }
        guard !quoted else { throw CSVBackupError.malformed }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
}
