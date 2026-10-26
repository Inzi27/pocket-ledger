import SwiftUI
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif
#if canImport(BudgetStore)
import BudgetStore
#endif

struct OverviewView: View {
    @Environment(\.ledgerPalette) private var palette
    @Query private var records: [LedgerEntry]
    @Query private var categoryRecords: [LedgerCategory]
    @Query private var budgetRecords: [MonthlyBudget]
    @State private var month = Date.now
    @State private var pickingMonth = false
    @AppStorage("lastFullBackup") private var lastBackup: Double = 0
    @AppStorage("backupReminderEnabled") private var backupReminder = false
    @State private var adding = false
    @State private var importing = false
    @State private var editing: LedgerEntry?
    private var entries: [LedgerEntry] { LedgerProjection.entries(records) }
    private var categories: [LedgerCategory] { LedgerProjection.categories(categoryRecords) }
    private var monthly: [LedgerEntry] {
        guard let range = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return entries.filter { $0.date >= range.start && $0.date < range.end }
    }
    private var expenses: Int64 { monthly.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountPaise } }
    private var refunds: Int64 { monthly.filter { $0.kind == .refund }.reduce(0) { $0 + $1.amountPaise } }
    private var breakdown: [(category: LedgerCategory, amount: Int64)] {
        categories.map { category in
            (category, monthly.filter { $0.categoryID == category.id && $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amountPaise })
        }.filter { $0.1 > 0 || monthlyBudgets[$0.0.id] != nil }.sorted { $0.1 > $1.1 }
    }
    private var monthlyBudgets: [String: Int64] {
        Dictionary(uniqueKeysWithValues: LedgerProjection.budgets(budgetRecords)
            .filter { $0.monthKey == LedgerStore.monthKey(for: month) }
            .map { ($0.categoryID, $0.amountPaise) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LedgerMonthSelector(month: $month, picking: $pickingMonth)
                spendingCard
                HStack(spacing: 12) {
                    Button { adding = true } label: {
                        Label("Add expense", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent)
                    Button { importing = true } label: {
                        Label("Import SMS", systemImage: "text.bubble").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.bordered)
                }
                HStack {
                    NavigationLink { PaymentAccountsView(initialMonth: month) } label: { Label("Cards & payments", systemImage: "creditcard") }
                    Spacer()
                    NavigationLink { ImportHistoryView() } label: { Label("Imports", systemImage: "clock.arrow.circlepath") }
                }.font(.subheadline)
                if backupReminder && Date.now.timeIntervalSince1970 - lastBackup >= 7 * 24 * 60 * 60 {
                    NavigationLink { BackupSettingsView() } label: {
                        Label(lastBackup == 0 ? "Create your first complete backup" : "Your weekly backup is due", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.subheadline).padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(palette.accent)
                        Text("A little clarity, every day.").font(.title3.bold())
                        Text("Add your first expense or connect bank messages to start seeing where your money goes.")
                            .foregroundStyle(.secondary)
                        NavigationLink { ShortcutSetupView() } label: { Label("Set up automatic imports", systemImage: "arrow.up.forward") }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 22))
                }
                if !breakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Where it went").font(.title3.bold())
                            Spacer()
                            Text("PURCHASES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        ForEach(breakdown, id: \.category.id) { item in
                            HStack(spacing: 12) {
                                CategoryIcon(symbol: item.category.symbol, tint: item.category.tint)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.category.name).font(.subheadline)
                                        Spacer()
                                        Text(Money.formatted(item.amount)).font(.subheadline.weight(.medium)).monospacedDigit()
                                    }
                                    GeometryReader { proxy in
                                        Capsule().fill(LedgerTheme.color(item.category.tint).opacity(0.12))
                                            .overlay(alignment: .leading) {
                                                Capsule().fill(LedgerTheme.color(item.category.tint))
                                                    .frame(width: proxy.size.width * CGFloat(item.amount) / CGFloat(max(expenses, 1)))
                                            }
                                    }.frame(height: 5).accessibilityHidden(true)
                                    if let limit = monthlyBudgets[item.category.id] {
                                        HStack {
                                            Text("Budget \(Money.formatted(limit))")
                                            Spacer()
                                            Text("\(Int((Double(item.amount) / Double(limit) * 100).rounded()))% used")
                                        }.font(.caption2).foregroundStyle(item.amount > limit ? Color.red : Color.gray)
                                        ProgressView(value: min(Double(item.amount) / Double(limit), 1))
                                            .tint(item.amount > limit ? .red : LedgerTheme.color(item.category.tint))
                                    }
                                }
                            }
                        }
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 22))
                }
                if !monthly.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Recent activity").font(.title3.bold())
                            Spacer()
                            NavigationLink("See all") { TransactionsView(initialMonth: month) }.font(.subheadline)
                        }
                        ForEach(Array(monthly.prefix(5))) { entry in
                            Button { editing = entry } label: {
                                TransactionRow(entry: entry, category: categories.first { $0.id == entry.categoryID })
                            }.buttonStyle(.plain)
                            if entry.id != monthly.prefix(5).last?.id { Divider() }
                        }
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 22))
                }
                Text("INR · Saved on your device · Made for your everyday")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 12)
            }.padding(20)
        }
        .background(LedgerTheme.background)
        .navigationTitle("Pocket Ledger")
        .sheet(isPresented: $adding) { NavigationStack { EntryEditor() } }
        .sheet(isPresented: $importing) { NavigationStack { ImportMessageView() } }
        .sheet(item: $editing) { entry in NavigationStack { EntryEditor(entry: entry) } }
        .sheet(isPresented: $pickingMonth) { MonthPickerSheet(month: $month) }
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("MONTHLY SPENDING").font(.caption.weight(.semibold)).tracking(1.6)
                Spacer()
                Image(systemName: "arrow.up.right.circle").font(.title2)
            }.foregroundStyle(.white.opacity(0.75))
            Text(Money.formatted(expenses - refunds)).font(.system(size: 43, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1).monospacedDigit().foregroundStyle(.white)
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Purchases").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(Money.formatted(expenses)).font(.subheadline.weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Refunds").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(Money.formatted(refunds)).font(.subheadline.weight(.semibold))
                }
                Spacer()
            }.foregroundStyle(.white)
            Text("Purchases minus refunds. Transfers and income are excluded.")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [palette.heroStart, palette.gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }

}
