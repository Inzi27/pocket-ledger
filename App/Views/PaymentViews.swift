import SwiftUI
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif
#if canImport(BudgetStore)
import BudgetStore
#endif

struct PaymentAccountsView: View {
    @Query private var records: [LedgerEntry]
    @Query private var accounts: [PaymentAccount]
    @State private var month = Date.now
    @State private var pickingMonth = false
    @State private var naming: PaymentGroup?
    init(initialMonth: Date = .now) { _month = State(initialValue: initialMonth) }
    private var entries: [LedgerEntry] { LedgerProjection.entries(records) }
    private var groups: [PaymentGroup] { PaymentGroup.groups(entries: entries, accounts: accounts) }
    private var monthly: [LedgerEntry] { entries.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) } }
    var body: some View {
        List {
            Section { LedgerMonthSelector(month: $month, picking: $pickingMonth) }
            Section {
                if groups.isEmpty {
                    ContentUnavailableView("No payments yet", systemImage: "creditcard",
                                           description: Text("Cards and payment methods appear after you add transactions."))
                }
                ForEach(groups) { group in
                    let matching = monthly.filter { PaymentGroup.key(for: $0) == group.id }
                    let purchases = matching.filter { $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amountPaise }
                    let refunds = matching.filter { $0.kind == .refund }.reduce(Int64(0)) { $0 + $1.amountPaise }
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink {
                            TransactionsView(initialMonth: month, initialAccountKey: group.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: group.symbol).font(.title2).frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name).font(.headline)
                                    if !group.nickname.isEmpty { Text(group.defaultName).font(.caption).foregroundStyle(.secondary) }
                                    Text("\(matching.count) transactions").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.formatted(purchases - refunds)).font(.subheadline.bold()).monospacedDigit()
                            }
                        }
                        HStack {
                            Text("Purchases \(Money.formatted(purchases)) · Refunds \(Money.formatted(refunds))")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { naming = group } label: { Text("Name").font(.caption).frame(minWidth: 44, minHeight: 44) }.buttonStyle(.borderless)
                                .accessibilityLabel("Name \(group.name)")
                        }
                    }.padding(.vertical, 4)
                }
            } footer: {
                Text("Totals are purchases minus refunds, not card balances or amounts due. Transfers and card repayments are excluded. Payments without last four digits are grouped by bank and method.")
            }
        }
        .navigationTitle("Cards & payments").ledgerBackground()
        .sheet(isPresented: $pickingMonth) { MonthPickerSheet(month: $month) }
        .sheet(item: $naming) { group in PaymentNicknameSheet(group: group) }
    }
}

private struct PaymentNicknameSheet: View {
    let group: PaymentGroup
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(group.defaultName).foregroundStyle(.secondary)
                    TextField("Nickname", text: $name)
                } footer: { Text("Use up to 40 characters. Leave blank to use the bank and payment details.") }
            }
            .navigationTitle("Payment nickname")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try LedgerStore.setNickname(name, for: group.id, in: context); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count > 40)
                }
            }
            .onAppear { name = group.nickname }
            .modifier(ErrorNotice(message: $error))
        }
    }
}

struct LedgerMonthSelector: View {
    @Binding var month: Date
    @Binding var picking: Bool
    var body: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous month")
            Spacer()
            Button { picking = true } label: {
                HStack(spacing: 5) {
                    Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                    Image(systemName: "chevron.down").font(.caption2)
                }.frame(minHeight: 44)
            }.accessibilityLabel("Choose month and year")
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Next month")
        }.buttonStyle(.borderless)
    }
    private func move(_ offset: Int) {
        let start = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
        month = Calendar.current.date(byAdding: .month, value: offset, to: start) ?? start
    }
}

struct MonthPickerSheet: View {
    @Binding var month: Date
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonth = 1
    @State private var year = 2026
    private var currentYear: Int { Calendar.current.component(.year, from: .now) }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Month", selection: $selectedMonth) {
                    ForEach(Array(Calendar.current.monthSymbols.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index + 1)
                    }
                }
                Picker("Year", selection: $year) {
                    ForEach(min(2000, year)...max(currentYear + 10, year), id: \.self) { Text(String($0)).tag($0) }
                }
                Button("This month") { month = .now; dismiss() }
            }
            .navigationTitle("Choose month")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        month = Calendar.current.date(from: DateComponents(year: year, month: selectedMonth, day: 1)) ?? month
                        dismiss()
                    }
                }
            }
            .onAppear { selectedMonth = Calendar.current.component(.month, from: month); year = Calendar.current.component(.year, from: month) }
        }.presentationDetents([.medium])
    }
}
