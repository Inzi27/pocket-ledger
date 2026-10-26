// Standalone checks for machines with Swift command-line tools but without XCTest/Xcode.
// Compiles and runs the actual BudgetCore module; no framework mocks are involved.
import Foundation
import BudgetCore

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}

@main struct CoreChecks {
    static func main() throws {
        let parser = MessageParser()
        let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        var passed = 0
        var failed: [String] = []
        func run(_ name: String, _ body: () throws -> Void) {
            do { try body(); passed += 1; print("PASS \(name)") }
            catch { failed.append(name + ": " + String(describing: error)); print("FAIL \(name): \(error)") }
        }
        func parse(_ text: String, sender: String = "") throws -> ParsedTransaction {
            guard case .transaction(let result) = parser.parse(text, sender: sender, receivedAt: now) else {
                throw CheckFailure(description: "Expected a transaction")
            }
            return result
        }
        run("HDFC amount excludes available limit") {
            let t = try parse("Spent Rs.1,250.50 on HDFC Bank Credit Card XX1234 at AMAZON on 24-10-2026. Avl Limit: Rs.98,749.50")
            try check(t.amountPaise == 125050 && t.merchant == "AMAZON" && t.accountSuffix == "1234" && !t.needsReview, "Incorrect HDFC purchase")
        }
        run("ICICI card used for amount") {
            let t = try parse("ICICI Bank Card XX5678 used for INR 499.00 at NETFLIX on 24-Oct-2026. Available limit INR 50,000.00.")
            try check(t.amountPaise == 49900 && t.merchant == "NETFLIX" && t.bank == .icici, "Incorrect ICICI purchase")
        }
        run("Axis card amount and merchant") {
            let t = try parse("INR 2,345.67 spent on Axis Bank Credit Card XX9012 at FLIPKART on 24/10/2026. Available Limit: INR 77,654.33")
            try check(t.amountPaise == 234567 && t.merchant == "FLIPKART" && t.bank == .axis, "Incorrect Axis purchase")
        }
        run("UPI debit ignores balance and flags transfer ambiguity") {
            let t = try parse("HDFC Bank: Rs.320.00 debited from a/c XX1234 to ZOMATO on 24-10-26. UPI Ref No 629812345678. Avl Bal Rs.12,345.00")
            try check(t.amountPaise == 32000 && t.merchant == "ZOMATO" && t.payment == .upi && t.needsReview, "Incorrect UPI purchase or merchant: \(t.merchant)")
        }
        run("Merchant follows account phrase") {
            let t = try parse("ICICI Bank: INR 250.00 debited from A/c XX1234 to SWIGGY on 24-10-2026. UPI Ref 629800000001.")
            try check(t.merchant == "SWIGGY", "Merchant: \(t.merchant)")
        }
        run("Refund classified separately") {
            let t = try parse("Refund of INR 500.00 credited to HDFC Bank Credit Card XX1234 from AMAZON on 24-10-2026.")
            try check(t.kind == .refund && t.amountPaise == 50000 && t.merchant == "AMAZON", "Refund merchant: \(t.merchant)")
        }
        run("Card repayment is a transfer") {
            let t = try parse("Payment of INR 12,000.00 received towards your ICICI Bank Credit Card XX5678 on 24-10-2026.")
            try check(t.kind == .transfer, "Repayment classified as \(t.kind)")
        }
        run("UPI credit is income") {
            let t = try parse("Axis Bank: INR 800.00 credited to A/c XX1234 from FRIEND on 24-10-2026. UPI Ref 629800000002.")
            try check(t.kind == .income && t.merchant == "FRIEND", "Income not recognized")
        }
        run("HDFC sent UPI template") {
            let t = try parse("Sent Rs.450.00 From HDFC Bank A/C *1234 To LOCAL SHOP On 24-10-2026 UPIRef 629812345671")
            try check(t.amountPaise == 45000 && t.merchant == "LOCAL SHOP" && t.payment == .upi && t.kind == .expense, "Sent template not recognized")
        }
        run("ICICI purchase skips the available limit and card-block phone") {
            let t = try parse("INR 209.00 spent using ICICI Bank Card XX9003 on 25-Oct-26 on RSP*SWIGGY PVT . Avl Limit: INR 9,76,331.63. If not you, call 1800 2662/SMS BLOCK 9003 to 9215676766")
            try check(t.amountPaise == 20900 && t.merchant == "RSP*SWIGGY PVT", "Amount or merchant incorrectly parsed as \(t.amountPaise) / \(t.merchant)")
            try check(t.bank == .icici && t.payment == .card && t.accountSuffix == "9003", "Card details not parsed")
            try check(!t.needsReview, "Unambiguous card purchase should not need review")
        }
        for (name, text) in [
            ("OTP", "OTP 987654 for INR 2000 purchase on HDFC card at AMAZON. Do not share."),
            ("Declined", "Your ICICI card transaction of INR 500 at AMAZON was declined."),
            ("Failed", "UPI payment of Rs.500 failed. HDFC account was not debited."),
            ("Bill reminder", "HDFC Credit Card total due INR 12000. Minimum due INR 600."),
            ("Mandate", "Your Axis UPI mandate for INR 500 will be debited tomorrow."),
            ("Collect request", "UPI collect request for Rs.1000 received from SHOP. ICICI Bank."),
            ("Purchase promotion", "Get INR 500 cashback on your next purchase with your HDFC card.")
        ] {
            run("Ignore " + name) { guard case .ignored = parser.parse(text, receivedAt: now) else { throw CheckFailure(description: "Should be ignored") } }
        }
        for (name, text) in [
            ("Ambiguous amount", "HDFC card purchase successful. INR 200 INR 300."),
            ("Zero", "Rs.0.00 spent on HDFC card at SHOP"),
            ("Foreign currency", "HDFC card spent USD 20. Available limit INR 50000."),
            ("Oversized input", String(repeating: "x", count: 20_000)),
            ("Empty input", "")
        ] {
            run("Reject " + name) { guard case .unrecognized = parser.parse(text, receivedAt: now) else { throw CheckFailure(description: "Should need manual entry") } }
        }
        run("Missing merchant is reviewable") {
            let t = try parse("INR 100 spent on HDFC Credit Card XX1234.")
            try check(t.needsReview && t.merchant == "Unknown merchant", "Should flag merchant")
        }
        run("Sender identifies bank") {
            let t = try parse("Rs.500 spent on card XX1234 at CAFE on 24-10-2026", sender: "VM-HDFCBK")
            try check(t.bank == .hdfc, "Sender not recognized")
        }
        run("References deduplicate formatting") {
            let a = try parse("HDFC UPI: INR 320 debited to ZOMATO on 24-10-2026. UPI Ref No 629812345678.")
            let b = try parse("Rs.320.00 debited from HDFC a/c XX1234 to ZOMATO on 24/10/2026. UPI Ref 629812345678.")
            try check(a.fingerprint == b.fingerprint, "Equivalent references must deduplicate")
        }
        run("Different references remain distinct") {
            let a = try parse("HDFC UPI INR 320 paid to ZOMATO. UPI Ref 629812345678")
            let b = try parse("HDFC UPI INR 320 paid to ZOMATO. UPI Ref 629812345679")
            try check(a.fingerprint != b.fingerprint, "Distinct references collapsed")
        }
        run("Refund does not collapse into original purchase") {
            let a = try parse("HDFC UPI INR 320 paid to ZOMATO. UPI Ref 629812345678")
            let b = try parse("HDFC UPI INR 320 refunded from ZOMATO. UPI Ref 629812345678")
            try check(a.fingerprint != b.fingerprint, "Refund collapsed")
        }
        run("Whitespace does not create duplicates") {
            let a = try parse("HDFC Card INR 320 spent at CAFE on 24-10-2026")
            let b = try parse("HDFC Card INR 320  spent\nat CAFE on 24-10-2026")
            try check(a.fingerprint == b.fingerprint, "Whitespace created duplicate")
        }
        run("Indian date and time") {
            let t = try parse("HDFC card INR 500 spent at CAFE on 24-10-2026 14:30:00.")
            try check(t.date == ISO8601DateFormatter().date(from: "2026-10-24T09:00:00Z")!, "Date/time incorrect")
        }
        run("Undated messages use receipt time") {
            let transaction = try parse("HDFC card INR 500 spent at CAFE.")
            try check(transaction.date == now, "Incorrect receipt time")
        }
        run("Exact integer paise and Indian grouping") {
            try check(Money.paise(from: "1,23,456.78") == 12345678 && Money.paise(from: "0.01") == 1 && Money.input(49901) == "499.01", "Money lost precision")
        }
        run("Reject invalid money") {
            for text in ["", "-1", "0", "1.234", "NaN", "inf", "1e9", "1000000001", "500 rupees"] { try check(Money.paise(from: text) == nil, "Accepted \(text)") }
        }
        run("Merchant categorization prioritizes groceries") {
            try check(MerchantCategory.suggested(for: "SWIGGY INSTAMART") == "groceries" && MerchantCategory.suggested(for: "Amazon India") == "shopping", "Wrong suggested category")
        }
        print("\n\(passed) checks passed; \(failed.count) failed.")
        if !failed.isEmpty { throw CheckFailure(description: failed.joined(separator: "\n")) }
    }
}
