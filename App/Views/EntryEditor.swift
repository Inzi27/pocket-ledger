import SwiftUI
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif
#if canImport(BudgetStore)
import BudgetStore
#endif

struct EntryEditor: View {
    var entry: LedgerEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var categoryRecords: [LedgerCategory]
    @State private var amount = ""
    @State private var merchant = ""
    @State private var date = Date.now
    @State private var kind = TransactionKind.expense
    @State private var payment = PaymentMethod.upi
    @State private var bank = Bank.unknown
    @State private var suffix = ""
    @State private var categoryID = "other"
    @State private var notes = ""
    @State private var remember = false
    @State private var reviewed = true
    @State private var loaded = false
    @State private var error: String?
    @State private var newCategory = false
    private var categories: [LedgerCategory] { LedgerProjection.categories(categoryRecords).filter { !$0.isArchived || $0.id == categoryID } }
    private var valid: Bool {
        Money.paise(from: amount) != nil && !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (suffix.isEmpty || (suffix.count == 4 && suffix.allSatisfy(\.isNumber)))
    }
    var body: some View {
        Form {
            if let entry, entry.needsReview {
                Section("Check these details") {
                    Label(entry.reviewReason, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                    Toggle("Mark as reviewed when saved", isOn: $reviewed)
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("₹").font(.largeTitle).foregroundStyle(.secondary)
                    TextField("0.00", text: $amount).font(.system(size: 36, weight: .semibold, design: .rounded)).amountKeyboard().accessibilityLabel("Amount in rupees")
                }.padding(.vertical, 8)
                TextField("Merchant or recipient", text: $merchant)
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                Picker("Type", selection: $kind) { ForEach(TransactionKind.allCases, id: \.self) { Text($0.label).tag($0) } }
            } footer: { Text("Refunds reduce spending. Income and transfers do not count as spending.") }
            Section("Category") {
                Picker("Category", selection: $categoryID) { ForEach(categories) { Text($0.name).tag($0.id) } }
                Button("Create a category", systemImage: "plus.circle") { newCategory = true }
                Toggle("Remember category for this merchant", isOn: $remember)
            }
            Section("Payment") {
                Picker("Method", selection: $payment) { ForEach(PaymentMethod.allCases, id: \.self) { Text($0.label).tag($0) } }
                if payment == .card || payment == .upi || payment == .other {
                    Picker("Bank", selection: $bank) { ForEach(Bank.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("Last 4 digits (optional)", text: $suffix).plainTextInput()
                }
            }
            Section("Notes") { TextField("Anything to remember?", text: $notes, axis: .vertical).lineLimit(3...6) }
            if entry?.source == "sms" {
                Section { Label("Imported from a bank message. Original SMS text is not stored.", systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .ledgerBackground()
        .navigationTitle(entry == nil ? "Add transaction" : "Edit transaction")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold).disabled(!valid) }
        }
        .onAppear(perform: populate)
        .sheet(isPresented: $newCategory) { NavigationStack { CategoryEditor(onSave: { categoryID = $0 }) } }
        .modifier(ErrorNotice(message: $error))
    }
    private func populate() {
        guard !loaded else { return }; loaded = true
        guard let entry else { return }
        amount = Money.input(entry.amountPaise); merchant = entry.merchant; date = entry.date
        kind = entry.kind; payment = entry.payment; bank = entry.bank; suffix = entry.accountSuffix
        categoryID = entry.categoryID; notes = entry.notes
    }
    private func save() {
        guard let paise = Money.paise(from: amount), valid else { return }
        let record = entry ?? LedgerEntry(amountPaise: paise, merchant: merchant, date: date)
        if entry == nil { context.insert(record) }
        record.amountPaise = paise; record.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        record.date = date; record.kindRaw = kind.rawValue; record.paymentRaw = payment.rawValue
        record.bankRaw = bank.rawValue; record.accountSuffix = suffix; record.categoryID = categoryID
        record.notes = notes; record.updatedAt = .now
        if reviewed { record.reviewReason = "" }
        do {
            if remember { try LedgerStore.remember(merchant: record.merchant, categoryID: categoryID, in: context) }
            try context.save()
            dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
