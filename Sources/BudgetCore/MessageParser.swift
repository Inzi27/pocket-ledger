import Foundation
import CryptoKit

public struct ParsedTransaction: Sendable {
    public let amountPaise: Int64
    public let merchant: String
    public let date: Date
    public let kind: TransactionKind
    public let payment: PaymentMethod
    public let bank: Bank
    public let accountSuffix: String
    public let fingerprint: String
    public let reviewReason: String
    public var needsReview: Bool { !reviewReason.isEmpty }
}

public enum ParseResult: Sendable {
    case transaction(ParsedTransaction)
    case ignored(String)
    case unrecognized(String)
}

/// Deliberately conservative: input is untrusted and never leaves this process.
public struct MessageParser: Sendable {
    public init() {}
    public func parse(_ message: String, sender: String = "", receivedAt: Date = .now) -> ParseResult {
        guard message.utf8.count <= 16_384 else { return .unrecognized("Message is too long.") }
        let text = message.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unrecognized("Paste a transaction message first.") }
        if matches(#"\b(OTP|one[ -]time password|verification code|one time pin)\b"#, text) {
            return .ignored("Verification messages are never imported.")
        }
        if matches(#"\b(failed|declined|unsuccessful|not processed|not debited|not successful|could not|attempted|will be debited|scheduled|mandate|payment request|collect request)\b"#, text) {
            return .ignored("This message does not confirm a completed payment.")
        }
        if matches(#"\b(amount due|total due|minimum due|payment due|statement generated|statement is|bill is due|credit limit increased|pre-approved|cashback offer|next purchase|next payment|spend and get|shop now)\b"#, text) {
            return .ignored("Bills, reminders, and offers are not new expenses.")
        }

        let combined = sender + " " + text
        let bank: Bank = matches("HDFC", combined) ? .hdfc : matches("ICICI", combined) ? .icici : matches("AXIS", combined) ? .axis : .unknown
        let payment: PaymentMethod = matches(#"\bUPI\b|UPI/|\bVPA\b|UPIRef"#, text) ? .upi : matches(#"\b(card|creditcard|visa|mastercard)\b"#, text) ? .card : .other
        let refund = matches(#"\b(refunded|refund|reversed|reversal)\b"#, text)
        let billPayment = matches(#"(?:payment|pymt).{0,45}(?:received|credited).{0,35}(?:card)|(?:payment|paid).{0,30}(?:towards|for|to).{0,25}(?:credit\s*card|card bill)|(?:credit\s*card|card).{0,30}(?:payment|pymt).{0,30}(?:received|credited|successful)"#, text)
        let credited = matches(#"\b(credited|received|deposited)\b"#, text)
        let debit = matches(#"\b(debited|spent|paid|sent|purchased|charged)\b|\bpurchase\b.{0,40}\b(successful|completed|confirmed)\b|\bused\b.{0,80}\b(at|for|INR|Rs)\b"#, text)
        guard refund || billPayment || credited || debit else {
            return .unrecognized("No completed transaction was found. You can add it manually.")
        }
        let kind: TransactionKind = refund ? .refund : billPayment ? .transfer : credited && !debit ? .income : .expense

        // Prefer an amount attached to the transaction verb, not a balance or limit.
        let currency = #"(?:INR\.?|Rs\.?|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)(?!\d|\.\d)"#
        let patterns = [
            #"(?:debited|spent|paid|sent|charged|refunded|credited|reversed|received)(?:\s+(?:by|with|for|of|amount|amt|successfully|is|was|has been))*\s*[:\-]?\s*"# + currency,
            currency + #"\s*(?:(?:has been|was|is|got)\s+)?(?:debited|spent|paid|charged|refunded|credited|reversed|received)\b"#,
            #"(?:txn|transaction|purchase|payment|pymt|refund)(?:\s+(?:of|for|amount|amt))?\s*[:\-]?\s*"# + currency,
            #"\bused\b.{0,65}?\bfor\s+"# + currency
        ]
        var amountText = patterns.compactMap { capture($0, text) }.first
        if amountText == nil {
            let candidates = captures(currency, text)
            // Multiple unexplained amounts must not guess at the available balance.
            if candidates.count == 1 { amountText = candidates.first }
        }
        guard let amountText, let amount = Money.paise(from: amountText) else {
            return .unrecognized("Could not identify a single INR transaction amount. Add this transaction manually.")
        }
        if matches(#"\b(USD|EUR|GBP|AED|SGD|AUD)\s*\d"#, text) {
            return .unrecognized("Foreign-currency transactions need a confirmed INR amount. Add this manually.")
        }

        let suffix = capture(#"(?:card|a/c|acct|account)(?:\s*(?:no\.?|number|ending|end|xx|x|\*|with|in|:|-|\.)\s*)*([0-9]{4})(?!\d)"#, text) ?? ""
        let reference = capture(#"(?:UPI\s*(?:Ref(?:erence)?(?:\s*No)?|txn(?:\s*id)?)|RRN|UTR|Ref(?:erence)?\s*(?:No|ID)?|Txn\s*ID)\s*[.:#\-]?\s*([A-Z0-9]{8,40})\b"#, text)
        let parsedDate = transactionDate(in: text, relativeTo: receivedAt)
        let date = parsedDate ?? receivedAt
        let candidates = captures(#"\b(?:at|to|towards|from|on)\s+(.+?)(?=\s+(?:at\b|to\b|from\b|on\b|using\b|via\b|with\b|thru\b|through\b|UPI\b|Ref\b|Txn\b|Avl\b|Available\b|Bal\b|Not\s+you\b|If\b|A/c\b)|[.;]|$)"#, text)
        var merchant = candidates.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-")) }.first {
            !$0.isEmpty && $0.count <= 100
                && !matches(#"^(?:your\b|a/c\b|account\b|card\b|INR\b|Rs\b|₹|\d{1,2}:)|(?:HDFC|ICICI|AXIS).{0,12}(?:Bank|Card)"#, $0)
                && !matches(#"^\d{1,4}[-/](?:\d{1,2}|[A-Za-z]{3})[-/]\d{2,4}(?:\s+\d{1,2}:\d{2})?$|^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?$"#, $0)
                && !matches(#"^(?:\+?\d[\d\s().-]{6,}\d|call\b|SMS\b|BLOCK\b)"#, $0)
                && !matches(#"^(?:an actual transaction|a transaction)"#, $0)
        } ?? ""
        var reasons: [String] = []
        if merchant.isEmpty { merchant = kind == .transfer ? "Card payment" : "Unknown merchant"; reasons.append("Merchant was not identified.") }
        if bank == .unknown { reasons.append("Bank was not identified.") }
        if payment == .other { reasons.append("Payment method needs checking.") }
        if kind == .expense && payment == .upi {
            // A debit SMS rarely proves whether a UPI recipient is your own account.
            reasons.append("Check whether this UPI payment is an expense or a transfer.")
        }
        if parsedDate == nil && matches(#"\b(?:on|dated)\s+\d{1,4}[-/]\d"#, text) {
            reasons.append("Message date was not recognized; received date was used.")
        }

        let key: String
        if let reference {
            key = "ref|\(bank.rawValue)|\(reference.uppercased())|\(kind.rawValue)|\(amount)"
        } else {
            let normalized = text.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            key = "text|\(bank.rawValue)|\(Self.dayKey(date))|\(normalized)"
        }
        let fingerprint = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return .transaction(.init(amountPaise: amount, merchant: merchant, date: date, kind: kind,
                                  payment: payment, bank: bank, accountSuffix: suffix,
                                  fingerprint: fingerprint, reviewReason: reasons.joined(separator: " ")))
    }

    private func transactionDate(in text: String, relativeTo received: Date) -> Date? {
        guard let raw = capture(#"\b(?:on|dated)\s+(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?|\d{1,2}[-/](?:\d{1,2}|[A-Za-z]{3})[-/]\d{2,4}(?:\s+(?:at\s+)?\d{2}:\d{2}(?::\d{2})?)?)"#, text) else { return nil }
        let normalized = raw.replacingOccurrences(of: " at ", with: " ")
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd",
                       "dd-MM-yyyy HH:mm:ss", "dd-MM-yyyy HH:mm", "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm",
                       "dd-MM-yy HH:mm:ss", "dd-MM-yy HH:mm", "dd/MM/yy HH:mm:ss", "dd/MM/yy HH:mm",
                       "dd-MMM-yyyy", "dd-MMM-yy", "dd-MM-yyyy", "dd/MM/yyyy", "dd-MM-yy", "dd/MM/yy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: normalized), date <= received.addingTimeInterval(86_400),
               date > Date(timeIntervalSince1970: 946_684_800) { return date }
        }
        return nil
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    private func capture(_ pattern: String, _ text: String) -> String? { captures(pattern, text).first }
    private func captures(_ pattern: String, _ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard $0.numberOfRanges > 1, let range = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}
