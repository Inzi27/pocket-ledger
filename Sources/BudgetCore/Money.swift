import Foundation

public enum Money {
    /// Store currency as integer paise, never floating-point rupees.
    public static func paise(from text: String) -> Int64? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard clean.range(of: #"^\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0, decimal <= Decimal(1_000_000_000) else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).int64Value
    }

    public static func input(_ paise: Int64) -> String {
        String(format: "%lld.%02lld", paise / 100, abs(paise % 100))
    }

    public static func formatted(_ paise: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "INR"
        formatter.locale = Locale(identifier: "en_IN")
        formatter.minimumFractionDigits = paise % 100 == 0 ? 0 : 2
        return formatter.string(from: NSDecimalNumber(value: paise).dividing(by: 100)) ?? "₹0"
    }
}

public enum TransactionKind: String, CaseIterable, Codable, Sendable {
    case expense, refund, income, transfer
    public var label: String { rawValue.capitalized }
}

public enum PaymentMethod: String, CaseIterable, Codable, Sendable {
    case upi, card, cash, other
    public var label: String { self == .upi ? "UPI" : rawValue.capitalized }
}

public enum Bank: String, CaseIterable, Codable, Sendable {
    case hdfc = "HDFC", icici = "ICICI", axis = "Axis", unknown = "Other"
}

public struct CategoryTemplate: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    public let tint: String
    public static let defaults: [CategoryTemplate] = [
        .init(id: "food", name: "Food & drinks", symbol: "fork.knife", tint: "orange"),
        .init(id: "groceries", name: "Groceries", symbol: "basket.fill", tint: "green"),
        .init(id: "transport", name: "Transport", symbol: "car.fill", tint: "blue"),
        .init(id: "shopping", name: "Shopping", symbol: "bag.fill", tint: "purple"),
        .init(id: "bills", name: "Bills & utilities", symbol: "bolt.fill", tint: "yellow"),
        .init(id: "health", name: "Health", symbol: "heart.fill", tint: "pink"),
        .init(id: "entertainment", name: "Entertainment", symbol: "play.tv.fill", tint: "indigo"),
        .init(id: "travel", name: "Travel", symbol: "airplane", tint: "teal"),
        .init(id: "other", name: "Uncategorized", symbol: "square.grid.2x2.fill", tint: "gray")
    ]
}

public enum MerchantCategory {
    public static func suggested(for merchant: String) -> String {
        let lower = merchant.lowercased()
        let mappings: [(String, [String])] = [
            ("groceries", ["blinkit", "zepto", "bigbasket", "dmart", "instamart", "reliance", "jiomart"]),
            ("food", ["swiggy", "zomato", "starbucks", "restaurant", "cafe", "domino", "kfc", "burger king", "mcdonalds"]),
            ("transport", ["uber", "ola cabs", "rapido", "metro", "petrol", "fuel", "shell", "hpcl", "bpcl"]),
            ("bills", ["airtel", "jio", "electricity", "broadband", "bescom", "tata power"]),
            ("entertainment", ["netflix", "spotify", "bookmyshow", "hotstar", "amazon prime"]),
            ("shopping", ["amazon", "flipkart", "myntra", "ajio", "meesho", "nykaa"]),
            ("health", ["pharmacy", "apollo", "hospital", "pharmeasy", "netmeds"]),
            ("travel", ["irctc", "indigo", "makemytrip", "air india", "hotel", "ole", "mmt"])
        ]

        for (category, keywords) in mappings {
            for keyword in keywords {
                if lower.contains(keyword) { return category }
            }
        }
        return "other"
    }

    public static func normalized(_ merchant: String) -> String {
        merchant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
