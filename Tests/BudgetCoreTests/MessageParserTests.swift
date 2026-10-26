import XCTest
@testable import BudgetCore

final class MessageParserTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
    let parser = MessageParser()

    func transaction(_ message: String, sender: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> ParsedTransaction {
        guard case .transaction(let value) = parser.parse(message, sender: sender, receivedAt: now) else {
            XCTFail("Expected a parsed transaction", file: file, line: line)
            throw NSError(domain: "ParseFailure", code: 1)
        }
        return value
    }

    func testHDFCPurchaseWithAvailableLimit() throws {
        let value = try transaction("Spent Rs.1,250.50 on HDFC Bank Credit Card XX1234 at AMAZON on 24-10-2026. Avl Limit: Rs.98,749.50")
        XCTAssertEqual(value.amountPaise, 125050)
        XCTAssertEqual(value.merchant, "AMAZON")
        XCTAssertEqual(value.bank, .hdfc)
        XCTAssertEqual(value.payment, .card)
        XCTAssertEqual(value.accountSuffix, "1234")
        XCTAssertEqual(value.kind, .expense)
        XCTAssertFalse(value.needsReview)
    }
    func testICICICardUsedForAmount() throws {
        let value = try transaction("ICICI Bank Card XX5678 used for INR 499.00 at NETFLIX on 24-Oct-2026. Available limit INR 50,000.00.")
        XCTAssertEqual(value.amountPaise, 49900)
        XCTAssertEqual(value.merchant, "NETFLIX")
        XCTAssertEqual(value.accountSuffix, "5678")
    }
    func testAxisPurchase() throws {
        let value = try transaction("INR 2,345.67 spent on Axis Bank Credit Card XX9012 at FLIPKART on 24/10/2026. Available Limit: INR 77,654.33")
        XCTAssertEqual(value.amountPaise, 234567)
        XCTAssertEqual(value.bank, .axis)
        XCTAssertEqual(value.accountSuffix, "9012")
        XCTAssertEqual(value.merchant, "FLIPKART")
    }
    func testUPIDebitAndBalance() throws {
        let value = try transaction("HDFC Bank: Rs.320.00 debited from a/c XX1234 to ZOMATO on 24-10-26. UPI Ref No 629812345678. Avl Bal Rs.12,345.00")
        XCTAssertEqual(value.amountPaise, 32000)
        XCTAssertEqual(value.payment, .upi)
        XCTAssertEqual(value.kind, .expense)
        XCTAssertTrue(value.needsReview)
    }
    func testUPIMerchantAfterAccountPhrase() throws {
        let value = try transaction("ICICI Bank: INR 250.00 debited from A/c XX1234 to SWIGGY on 24-10-2026. UPI Ref 629800000001.")
        XCTAssertEqual(value.merchant, "SWIGGY")
    }
    func testRefundReducesExpenses() throws {
        let value = try transaction("Refund of INR 500.00 credited to HDFC Bank Credit Card XX1234 from AMAZON on 24-10-2026.")
        XCTAssertEqual(value.kind, .refund)
        XCTAssertEqual(value.amountPaise, 50000)
    }
    func testCardBillPaymentIsTransfer() throws {
        let value = try transaction("Payment of INR 12,000.00 received towards your ICICI Bank Credit Card XX5678 on 24-10-2026.")
        XCTAssertEqual(value.kind, .transfer)
    }
    func testUPIIncome() throws {
        let value = try transaction("Axis Bank: INR 800.00 credited to A/c XX1234 from FRIEND on 24-10-2026. UPI Ref 629800000002.")
        XCTAssertEqual(value.kind, .income)
    }
    func testHDFCSentUPITemplate() throws {
        let value = try transaction("Sent Rs.450.00 From HDFC Bank A/C *1234 To LOCAL SHOP On 24-10-2026 UPIRef 629812345671")
        XCTAssertEqual(value.amountPaise, 45000)
        XCTAssertEqual(value.payment, .upi)
        XCTAssertEqual(value.merchant, "LOCAL SHOP")
    }
    func testICICIMerchantBeforeAvailableLimitAndBlockPhoneNumber() throws {
        let value = try transaction("INR 209.00 spent using ICICI Bank Card XX9003 on 25-Oct-26 on RSP*SWIGGY PVT . Avl Limit: INR 9,76,331.63. If not you, call 1800 2662/SMS BLOCK 9003 to 9215676766")
        XCTAssertEqual(value.amountPaise, 20900)
        XCTAssertEqual(value.merchant, "RSP*SWIGGY PVT")
        XCTAssertEqual(value.bank, .icici)
        XCTAssertEqual(value.payment, .card)
        XCTAssertEqual(value.accountSuffix, "9003")
        XCTAssertEqual(value.date, ISO8601DateFormatter().date(from: "2026-10-24T18:30:00Z")!)
        XCTAssertFalse(value.needsReview)
    }
    func testSenderIdentifiesBank() throws {
        let value = try transaction("Rs.500 spent on card XX1234 at CAFE on 24-10-2026", sender: "VM-HDFCBK")
        XCTAssertEqual(value.bank, .hdfc)
    }
    func testOTPIsIgnoredEvenWithAmountAndMerchant() {
        assertIgnored("OTP 987654 for INR 2000 purchase on HDFC card at AMAZON. Do not share.")
    }
    func testFailedPaymentIsIgnored() {
        assertIgnored("Your ICICI card transaction of INR 500 at AMAZON was declined.")
        assertIgnored("UPI payment of Rs.500 failed. Your HDFC account was not debited.")
    }
    func testBillReminderIsIgnored() {
        assertIgnored("HDFC Credit Card total due INR 12000. Minimum due INR 600.")
    }
    func testMandateIsIgnored() {
        assertIgnored("Your Axis UPI mandate for INR 500 will be debited tomorrow.")
    }
    func testPromotionIsNotAPurchase() {
        assertIgnored("Get INR 500 cashback on your next purchase with your HDFC card.")
    }
    func testPaymentRequestIsIgnored() {
        assertIgnored("UPI collect request for Rs.1000 received from SHOP. ICICI Bank.")
    }
    func testMultipleAmountsWithoutTransactionAnchorAreNotGuessed() {
        guard case .unrecognized = parser.parse("HDFC card purchase successful. INR 200 INR 300.") else { return XCTFail("Must not guess the amount") }
    }
    func testZeroAmountIsRejected() {
        guard case .unrecognized = parser.parse("Rs.0.00 spent on HDFC card at SHOP") else { return XCTFail("Zero is not an expense") }
    }
    func testMissingMerchantIsSavedForReview() throws {
        let value = try transaction("INR 100 spent on HDFC Credit Card XX1234.")
        XCTAssertTrue(value.needsReview)
        XCTAssertEqual(value.merchant, "Unknown merchant")
    }
    func testForeignCurrencyIsNotMistakenForINRBalance() {
        guard case .unrecognized = parser.parse("HDFC card spent USD 20. Available limit INR 50000.") else { return XCTFail("Foreign amount must need manual entry") }
    }
    func testReferenceDeduplicatesFormattingDifferences() throws {
        let a = try transaction("HDFC UPI: INR 320 debited to ZOMATO on 24-10-2026. UPI Ref No 629812345678.")
        let b = try transaction("Rs.320.00 debited from HDFC a/c XX1234 to ZOMATO on 24/10/2026. UPI Ref 629812345678.")
        XCTAssertEqual(a.fingerprint, b.fingerprint)
    }
    func testDifferentReferencesRemainDistinct() throws {
        let a = try transaction("HDFC UPI INR 320 paid to ZOMATO. UPI Ref 629812345678")
        let b = try transaction("HDFC UPI INR 320 paid to ZOMATO. UPI Ref 629812345679")
        XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }
    func testRefundDoesNotDeduplicateAgainstExpense() throws {
        let a = try transaction("HDFC UPI INR 320 paid to ZOMATO. UPI Ref 629812345678")
        let b = try transaction("HDFC UPI INR 320 refunded from ZOMATO. UPI Ref 629812345678")
        XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }
    func testWhitespaceDoesNotCreateDuplicate() throws {
        let a = try transaction("HDFC Card INR 320 spent at CAFE on 24-10-2026")
        let b = try transaction("HDFC Card INR 320  spent\nat CAFE on 24-10-2026")
        XCTAssertEqual(a.fingerprint, b.fingerprint)
    }
    func testIndianDateAndTime() throws {
        let value = try transaction("HDFC card INR 500 spent at CAFE on 24-10-2026 14:30:00.")
        XCTAssertEqual(value.date, ISO8601DateFormatter().date(from: "2026-10-24T09:00:00Z")!)
    }
    func testUndatedMessageUsesReceivedDate() throws {
        let value = try transaction("HDFC card INR 500 spent at CAFE.")
        XCTAssertEqual(value.date, now)
    }
    func testOversizedInputIsRejected() {
        guard case .unrecognized = parser.parse(String(repeating: "x", count: 20_000)) else { return XCTFail("Input must be bounded") }
    }
    private func assertIgnored(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .ignored = parser.parse(text, receivedAt: now) else { return XCTFail("Expected message to be ignored", file: file, line: line) }
    }
}

final class MoneyTests: XCTestCase {
    func testPaiseAreExact() {
        XCTAssertEqual(Money.paise(from: "1,23,456.78"), 12345678)
        XCTAssertEqual(Money.paise(from: "0.01"), 1)
        XCTAssertEqual(Money.paise(from: "499"), 49900)
        XCTAssertEqual(Money.input(49901), "499.01")
    }
    func testInvalidInputs() {
        for text in ["", "-1", "0", "1.234", "NaN", "inf", "1e9", "1000000001", "500 rupees"] { XCTAssertNil(Money.paise(from: text), text) }
    }
    func testCategorySuggestions() {
        XCTAssertEqual(MerchantCategory.suggested(for: "SWIGGY INSTAMART"), "groceries")
        XCTAssertEqual(MerchantCategory.suggested(for: "Amazon India"), "shopping")
        XCTAssertEqual(MerchantCategory.suggested(for: "Unknown Person"), "other")
    }
}
