import SwiftUI
import SwiftData
#if canImport(BudgetCore)
import BudgetCore
#endif
#if canImport(BudgetStore)
import BudgetStore
#endif

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [LedgerCategory]
    @State private var editing: LedgerCategory?
    @State private var adding = false
    @State private var error: String?
    private var categories: [LedgerCategory] { LedgerProjection.categories(records) }
    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button { editing = category } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(symbol: category.symbol, tint: category.tint)
                            Text(category.name).foregroundStyle(.primary)
                            Spacer()
                            if category.isArchived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                .onMove { source, destination in
                    var sorted = categories
                    sorted.move(fromOffsets: source, toOffset: destination)
                    for (index, category) in sorted.enumerated() { category.order = index; category.updatedAt = .now }
                    do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
                }
            } footer: { Text("Archived categories keep their history but won’t be assigned to new imports.") }
        }
        .ledgerBackground().navigationTitle("Categories")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) { EditButton() }
            #endif
            ToolbarItem(placement: .primaryAction) { Button("Add category", systemImage: "plus") { adding = true } }
        }
        .sheet(isPresented: $adding) { NavigationStack { CategoryEditor() } }
        .sheet(item: $editing) { category in NavigationStack { CategoryEditor(category: category) } }
        .modifier(ErrorNotice(message: $error))
    }
}

struct CategoryEditor: View {
    @Environment(\.ledgerPalette) private var palette
    var category: LedgerCategory?
    var onSave: ((String) -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [LedgerCategory]
    @State private var name = ""
    @State private var symbol = "tag.fill"
    @State private var tint = "teal"
    @State private var archived = false
    @State private var error: String?
    @State private var loaded = false
    private let symbols = ["tag.fill", "fork.knife", "basket.fill", "car.fill", "bag.fill", "bolt.fill", "heart.fill", "play.tv.fill", "airplane", "house.fill", "graduationcap.fill", "gift.fill", "pawprint.fill", "sportscourt.fill", "cup.and.saucer.fill", "banknote.fill"]
    private let colors = ["teal", "orange", "green", "blue", "purple", "yellow", "pink", "indigo", "gray"]
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicateName: Bool {
        LedgerProjection.categories(records).contains { $0.id != category?.id && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }
    }
    var body: some View {
        Form {
            Section {
                HStack { Spacer(); CategoryIcon(symbol: symbol, tint: tint).scaleEffect(1.4).padding(20); Spacer() }
                TextField("Category name", text: $name)
                if duplicateName { Text("A category with this name already exists.").font(.caption).foregroundStyle(.orange) }
            }
            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                    ForEach(symbols, id: \.self) { item in
                        Button { symbol = item } label: {
                            Image(systemName: item).font(.title3).frame(width: 44, height: 44)
                                .background(symbol == item ? palette.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel(item.replacingOccurrences(of: ".fill", with: ""))
                            .accessibilityAddTraits(symbol == item ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            }
            Section("Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                    ForEach(colors, id: \.self) { item in
                        Button { tint = item } label: {
                            Circle().fill(LedgerTheme.color(item)).frame(width: 34, height: 34)
                                .overlay { if tint == item { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white) } }
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(item).accessibilityAddTraits(tint == item ? .isSelected : [])
                    }
                }
            }
            if let category, category.id != "other" {
                Section { Toggle("Archive category", isOn: $archived) } footer: { Text("Existing transactions keep this category.") }
            }
        }
        .ledgerBackground().navigationTitle(category == nil ? "New category" : "Edit category")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(cleanName.isEmpty || duplicateName) }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let category { name = category.name; symbol = category.symbol; tint = category.tint; archived = category.isArchived }
        }
        .modifier(ErrorNotice(message: $error))
    }
    private func save() {
        guard !cleanName.isEmpty, !duplicateName else { return }
        let record = category ?? LedgerCategory(name: cleanName, order: (records.map(\.order).max() ?? 0) + 1)
        if category == nil { context.insert(record) }
        record.name = cleanName; record.symbol = symbol; record.tint = tint; record.isArchived = archived; record.updatedAt = .now
        do { try context.save(); onSave?(record.id); dismiss() }
        catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct MerchantRulesView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [MerchantRule]
    @Query private var categories: [LedgerCategory]
    @State private var error: String?
    private var rules: [MerchantRule] { LedgerProjection.rules(records) }
    var body: some View {
        List {
            Section {
                if rules.isEmpty {
                    ContentUnavailableView("No merchant rules yet", systemImage: "arrow.triangle.branch", description: Text("When editing a transaction, enable ‘Remember category for this merchant’ to categorize future imports."))
                }
                ForEach(rules, id: \.merchantKey) { rule in
                    HStack {
                        Text(rule.merchantKey)
                        Spacer()
                        Text(LedgerProjection.categories(categories).first { $0.id == rule.categoryID }?.name ?? "Uncategorized").foregroundStyle(.secondary)
                    }.swipeActions { Button("Remove", role: .destructive) { remove(rule) } }
                }
            } footer: { Text("Rules match the merchant name exactly, ignoring case and extra spaces. Change a rule by saving a new category for that merchant.") }
        }.ledgerBackground().navigationTitle("Merchant rules").modifier(ErrorNotice(message: $error))
    }
    private func remove(_ rule: MerchantRule) {
        for record in records where record.merchantKey == rule.merchantKey { record.isDeleted = true; record.updatedAt = .now }
        do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
