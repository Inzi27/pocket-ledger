import SwiftUI
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif
#if canImport(BudgetStore)
import BudgetStore
#endif

struct TransactionsView: View {
    var reviewOnly = false
    @Environment(\.modelContext) private var context
    @Query private var records: [LedgerEntry]
    @Query private var categoryRecords: [LedgerCategory]
    @Query private var accountRecords: [PaymentAccount]
    @State private var search = ""
    @State private var kindFilter = "all"
    @State private var categoryFilter = "all"
    @State private var selectedMonth = Date.now
    @State private var dateScope = LedgerDateScope.month
    @State private var rangeStart = Date.now
    @State private var rangeEnd = Date.now
    @State private var paymentFilter = "all"
    @State private var bankFilter = "all"
    @State private var accountFilter = ""
    @State private var pickingMonth = false
    @AppStorage("transactionsChartExpanded") private var chartExpanded = true
    @State private var editing: LedgerEntry?
    @State private var deleting: LedgerEntry?
    @State private var adding = false
    @State private var importing = false
    @State private var error: String?
    init(reviewOnly: Bool = false, initialMonth: Date = .now, initialAccountKey: String = "") {
        self.reviewOnly = reviewOnly
        _selectedMonth = State(initialValue: initialMonth)
        _dateScope = State(initialValue: reviewOnly ? .allTime : .month)
        _accountFilter = State(initialValue: initialAccountKey)
        let range = Calendar.current.dateInterval(of: .month, for: initialMonth)
        _rangeStart = State(initialValue: range?.start ?? initialMonth)
        _rangeEnd = State(initialValue: range?.end.addingTimeInterval(-1) ?? initialMonth)
    }
    private var categories: [LedgerCategory] { LedgerProjection.categories(categoryRecords) }
    private var entries: [LedgerEntry] { LedgerProjection.entries(records) }
    private var paymentGroups: [PaymentGroup] { PaymentGroup.groups(entries: entries, accounts: accountRecords) }
    private var hasFilters: Bool { kindFilter != "all" || categoryFilter != "all" || paymentFilter != "all" || bankFilter != "all" || !accountFilter.isEmpty || !search.isEmpty }
    // Keep category selection out of the chart's data so every slice stays tappable.
    private var chartEntries: [LedgerEntry] {
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let accountNames = Dictionary(uniqueKeysWithValues: LedgerProjection.accounts(accountRecords).map { ($0.key, $0.nickname) })
        return entries.filter { entry in
            let inRange = dateScope.contains(entry.date, month: selectedMonth, start: rangeStart, end: rangeEnd)
            let key = PaymentGroup.key(for: entry)
            return inRange && (!reviewOnly || entry.needsReview) && (kindFilter == "all" || entry.kindRaw == kindFilter)
            && (paymentFilter == "all" || entry.paymentRaw == paymentFilter)
            && (bankFilter == "all" || entry.bankRaw == bankFilter)
            && (accountFilter.isEmpty || key == accountFilter)
            && (search.isEmpty || [entry.merchant, entry.notes, entry.bankRaw, entry.accountSuffix,
                                  categoryNames[entry.categoryID] ?? "", entry.payment.label,
                                  accountNames[key] ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    private var filtered: [LedgerEntry] {
        chartEntries.filter { categoryFilter == "all" || $0.categoryID == categoryFilter }
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $dateScope) {
                    ForEach(LedgerDateScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if dateScope == .month {
                    LedgerMonthSelector(month: $selectedMonth, picking: $pickingMonth)
                } else if dateScope == .custom {
                    DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                    DatePicker("Through", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)
                }
            }
            if hasFilters {
                Section {
                    if let group = paymentGroups.first(where: { $0.id == accountFilter }) { Label(group.name, systemImage: group.symbol) }
                    if paymentFilter != "all" { Text(PaymentMethod(rawValue: paymentFilter)?.label ?? paymentFilter) }
                    if bankFilter != "all" { Text(bankFilter) }
                    if let category = categories.first(where: { $0.id == categoryFilter }) { Text(category.name) }
                    if kindFilter != "all" { Text(TransactionKind(rawValue: kindFilter)?.label ?? kindFilter) }
                    Button("Clear filters", systemImage: "xmark.circle") { resetFilters() }
                }.font(.subheadline)
            }
            if !reviewOnly {
                Section {
                    DisclosureGroup("Spending chart", isExpanded: $chartExpanded) {
                        SpendingChart(entries: chartEntries, categories: categories, selectedCategoryID: categoryFilter == "all" ? nil : categoryFilter) { categoryID in
                            categoryFilter = categoryID
                        }
                    }
                }
            }
            if reviewOnly && !filtered.isEmpty {
                Section {
                    Text("These imports are already saved. Open Edit details to correct the merchant, amount, date, payment type, or category. Tap Looks good when the details are confirmed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(reviewOnly && !entries.contains(where: \.needsReview) ? "All caught up" : "No matching transactions", systemImage: reviewOnly ? "checkmark.seal" : "tray")
                } description: {
                    Text(reviewOnly && !entries.contains(where: \.needsReview) ? "All imported transactions have been reviewed." : "Try another period or clear your filters.")
                }.listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: reviewOnly ? 8 : 0) {
                            Button { editing = entry } label: {
                                TransactionRow(entry: entry, category: categories.first { $0.id == entry.categoryID })
                            }.buttonStyle(.plain)
                            if reviewOnly {
                                if !entry.reviewReason.isEmpty {
                                    Label(entry.reviewReason, systemImage: "exclamationmark.circle.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                                HStack {
                                    Button("Edit details", systemImage: "pencil") { editing = entry }
                                        .buttonStyle(.bordered)
                                    Button("Looks good", systemImage: "checkmark") { markReviewed(entry) }
                                        .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: reviewOnly ? 6 : 4, leading: 16, bottom: reviewOnly ? 6 : 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash") { deleting = entry }
                                .tint(.red)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(filtered.count) transactions")
                        Spacer()
                        Text("Spending \(Money.formatted(LedgerProjection.netSpending(filtered)))")
                    }
                }
            }
        }
        .ledgerBackground()
        .navigationTitle(reviewOnly ? "Review imports" : "Transactions")
        .searchable(text: $search, prompt: "Merchant, card, category, or notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Transaction type", selection: $kindFilter) {
                        Text("All types").tag("all")
                        ForEach(TransactionKind.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Category", selection: $categoryFilter) {
                        Text("All categories").tag("all")
                        ForEach(categories) { Text($0.name).tag($0.id) }
                    }
                    Picker("Payment method", selection: $paymentFilter) {
                        Text("All methods").tag("all")
                        ForEach(PaymentMethod.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Bank", selection: $bankFilter) {
                        Text("All banks").tag("all")
                        ForEach(Bank.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Card or account", selection: $accountFilter) {
                        Text("All cards and accounts").tag("")
                        ForEach(paymentGroups) { Text($0.name).tag($0.id) }
                    }
                    if hasFilters {
                        Button("Clear filters", systemImage: "arrow.counterclockwise") { resetFilters() }
                    }
                } label: { Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                .accessibilityLabel("Filter transactions")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add manually", systemImage: "plus") { adding = true }
                    Button("Import message", systemImage: "text.bubble") { importing = true }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Add transaction")
            }
        }
        .sheet(item: $editing) { entry in NavigationStack { EntryEditor(entry: entry) } }
        .sheet(isPresented: $adding) { NavigationStack { EntryEditor() } }
        .sheet(isPresented: $importing) { NavigationStack { ImportMessageView() } }
        .sheet(isPresented: $pickingMonth) { MonthPickerSheet(month: $selectedMonth) }
        .onChange(of: rangeStart) { _, start in if rangeEnd < start { rangeEnd = start } }
        .alert("Delete transaction?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { entry in
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                do { try LedgerStore.delete(entry, in: context) } catch { self.error = error.localizedDescription }
                deleting = nil
            }
        } message: { entry in
            Text("\(entry.merchant)\n\(Money.formatted(entry.amountPaise)) · \(entry.date.formatted(date: .abbreviated, time: .omitted))\n\nThis removes the transaction from your ledger.")
        }
        .modifier(ErrorNotice(message: $error))
    }
    private func markReviewed(_ entry: LedgerEntry) {
        entry.reviewReason = ""; entry.updatedAt = .now
        do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func resetFilters() {
        kindFilter = "all"; categoryFilter = "all"; paymentFilter = "all"; bankFilter = "all"; accountFilter = ""; search = ""
    }
}
