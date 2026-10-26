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
    @State private var search = ""
    @State private var kindFilter = "all"
    @State private var categoryFilter = "all"
    @State private var selectedMonth = Date.now
    @State private var editing: LedgerEntry?
    @State private var deleting: LedgerEntry?
    @State private var adding = false
    @State private var importing = false
    @State private var error: String?
    private var categories: [LedgerCategory] { LedgerProjection.categories(categoryRecords) }
    // Keep category selection out of the chart's data so every slice stays tappable.
    private var chartEntries: [LedgerEntry] {
        LedgerProjection.entries(records).filter { entry in
            let calendar = Calendar.current
            let isSameMonth = calendar.isDate(entry.date, equalTo: selectedMonth, toGranularity: .month)
            return isSameMonth && (!reviewOnly || entry.needsReview) && (kindFilter == "all" || entry.kindRaw == kindFilter)
            && (search.isEmpty || [entry.merchant, entry.notes, entry.bankRaw, entry.accountSuffix, categories.first { $0.id == entry.categoryID }?.name ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    private var filtered: [LedgerEntry] {
        chartEntries.filter { categoryFilter == "all" || $0.categoryID == categoryFilter }
    }

    var body: some View {
        List {
            Section {
                SpendingChart(entries: chartEntries, categories: categories, selectedCategoryID: categoryFilter == "all" ? nil : categoryFilter) { categoryID in
                    categoryFilter = categoryID
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                HStack {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }.buttonStyle(.borderless).accessibilityLabel("Previous month")
                    Spacer()
                    Text(selectedMonth, format: .dateTime.month(.wide).year()).font(.headline)
                    Spacer()
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }.buttonStyle(.borderless).accessibilityLabel("Next month")
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
                    Label(reviewOnly ? "All caught up" : "No transactions yet", systemImage: reviewOnly ? "checkmark.seal" : "tray")
                } description: {
                    Text(search.isEmpty && kindFilter == "all" && categoryFilter == "all" ? (reviewOnly ? "Imported transactions that need a second look will appear here." : "Add an expense or import a bank message.") : "Try another search or filter.")
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
                } header: { Text("\(filtered.count) transactions") }
            }
        }
        .ledgerBackground()
        .navigationTitle(reviewOnly ? "Review imports" : "Transactions")
        .searchable(text: $search, prompt: "Merchant, bank, category, or notes")
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
                    if kindFilter != "all" || categoryFilter != "all" || search != "" || Calendar.current.isDate(selectedMonth, equalTo: Date.now, toGranularity: .month) == false {
                        Button("Reset filters", systemImage: "arrow.counterclockwise") { kindFilter = "all"; categoryFilter = "all"; search = ""; selectedMonth = Date.now }
                    }
                } label: { Image(systemName: kindFilter == "all" && categoryFilter == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
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
    private func moveMonth(_ offset: Int) {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
        selectedMonth = calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }
}
