import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalAuthentication
#if canImport(BudgetCore)
import BudgetCore
#endif
#if canImport(BudgetStore)
import BudgetStore
#endif

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct SettingsView: View {
    @Environment(\.ledgerPalette) private var palette
    @EnvironmentObject private var runtime: AppRuntime
    @Environment(\.modelContext) private var context
    @Query private var records: [LedgerEntry]
    @Query private var categories: [LedgerCategory]
    @AppStorage("appLockEnabled") private var lockEnabled = false
    @AppStorage("appThemeColor") private var themeName = AppTheme.teal.rawValue
    @AppStorage("appAppearance") private var appearanceName = AppAppearance.system.rawValue
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exporting = false
    @State private var selectingCSV = false
    @State private var showingCSVPreview = false
    @State private var csvPreview: CSVImportPreview?
    @State private var csvResult: String?
    @State private var clearing = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pocket Ledger").font(.headline)
                        Text("A clear view of your everyday spending.").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "indianrupeesign.circle.fill").font(.title).foregroundStyle(palette.accent) }
                LabeledContent("Currency", value: "Indian rupee · INR")
            }
            Section("Make it yours") {
                NavigationLink { CategoriesView() } label: { Label("Categories", systemImage: "square.grid.2x2") }
                NavigationLink { MerchantRulesView() } label: { Label("Merchant rules", systemImage: "arrow.triangle.branch") }
                NavigationLink { BudgetSettingsView() } label: { Label("Monthly category budgets", systemImage: "chart.bar.fill") }
                NavigationLink { ShortcutSetupView() } label: { Label("Automatic imports", systemImage: "bolt") }
                NavigationLink { ImportHistoryView() } label: { Label("Import activity", systemImage: "clock.arrow.circlepath") }
                NavigationLink { PaymentAccountsView() } label: { Label("Cards & payments", systemImage: "creditcard") }

            }
            Section("Appearance") {
                Picker("Color theme", selection: $themeName) {
                    ForEach(AppTheme.allCases) { theme in
                        Label {
                            Text(theme.label)
                        } icon: {
                            theme.menuSwatch
                        }.tag(theme.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Picker("Display", selection: $appearanceName) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("iCloud") {
                Label(runtime.cloudEnabled ? "Private iCloud sync enabled" : "Local storage build", systemImage: runtime.cloudEnabled ? "icloud" : "iphone")
                Text(runtime.syncStatus).font(.subheadline).foregroundStyle(.secondary)
                if let lastSync = runtime.lastSync {
                    LabeledContent("Last completed activity") { Text(lastSync, style: .relative).font(.caption) }
                }
                if runtime.cloudEnabled {
                    Button("Check iCloud account") { Task { await runtime.checkCloudAccount() } }
                    Text("Changes sync automatically with your own devices using the same Apple Account. iCloud decides when to transfer changes; account availability does not mean every change has synced.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("To enable sync, build the PocketLedger iCloud scheme with your Apple Developer team and a private CloudKit container. Your local ledger stays in the same store.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                Toggle("Require device unlock", isOn: Binding(get: { lockEnabled }, set: { enabled in Task { await setLock(enabled) } }))
                Text("Face ID or your device passcode protects the app screen. Shortcuts can continue importing in the background after the first unlock following a restart.")
                    .font(.caption).foregroundStyle(.secondary)
                NavigationLink("How your data is handled") { PrivacyView() }
            }
            Section("Your data") {
                NavigationLink { BackupSettingsView() } label: { Label("Complete backup & restore", systemImage: "externaldrive") }
                Button("Export transactions as CSV", systemImage: "square.and.arrow.up") {
                    exportDocument = CSVDocument(text: LedgerStore.csv(entries: records, categories: categories)); exporting = true
                }
                Button("Import transactions from CSV", systemImage: "square.and.arrow.down") { selectingCSV = true }
                if let csvResult { Text(csvResult).font(.caption).foregroundStyle(.secondary) }
                Button("Delete all transactions", role: .destructive) { clearing = true }
            }
            Section { Text("Version 1.0 · Built for iPhone by inzi · INR only").font(.caption).foregroundStyle(.secondary) }
        }
        .ledgerBackground().navigationTitle("Settings")
        .task { await runtime.checkCloudAccount() }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "PocketLedger-transactions") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .fileImporter(isPresented: $selectingCSV, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 10_000_000 else { throw CSVBackupError.tooLarge }
                guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else { throw CSVBackupError.malformed }
                csvPreview = try CSVBackup.preview(text, existingEntries: records, categories: categories)
                showingCSVPreview = true
            } catch {
                let nsError = error as NSError
                if !(error is CancellationError) && nsError.code != -128 { self.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showingCSVPreview, onDismiss: { csvPreview = nil }) {
            if let csvPreview {
                CSVImportPreviewSheet(preview: csvPreview) { result in
                    csvResult = result
                }
            }
        }
        .confirmationDialog("Delete every transaction?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Delete all transactions", role: .destructive, action: clearTransactions)
        } message: { Text("This cannot be undone. It also deletes transactions on your synced devices. Export a copy first if you want to keep them. Categories, merchant rules, and monthly budgets remain.") }
        .modifier(ErrorNotice(message: $error))
    }
    @MainActor private func setLock(_ enabled: Bool) async {
        do {
            if try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Change Pocket Ledger’s privacy lock") { lockEnabled = enabled }
        } catch { self.error = "Device authentication was not completed. The lock setting was not changed." }
    }
    private func clearTransactions() {
        for record in records {
            record.markDeleted()
        }
        do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

private struct BudgetSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var categoryRecords: [LedgerCategory]
    @Query private var budgetRecords: [MonthlyBudget]
    @State private var month = Date.now
    @State private var drafts: [String: String] = [:]
    @State private var error: String?

    private var categories: [LedgerCategory] { LedgerProjection.categories(categoryRecords).filter { !$0.isArchived } }
    private var monthKey: String { LedgerStore.monthKey(for: month) }
    private var budgets: [MonthlyBudget] { LedgerProjection.budgets(budgetRecords).filter { $0.monthKey == monthKey } }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                    Spacer()
                    Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                    Spacer()
                    Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
                }
                Text("Set a monthly limit for each category. Leave a field blank or enter zero to remove its budget.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(categories) { category in
                let saved = budgets.first { $0.categoryID == category.id }?.amountPaise ?? 0
                Section(category.name) {
                    HStack {
                        Text("₹")
                        TextField("No budget", text: Binding(
                            get: { drafts[category.id] ?? (saved > 0 ? Money.input(saved) : "") },
                            set: { drafts[category.id] = $0 }
                        )).amountKeyboard().accessibilityLabel("Monthly budget for \(category.name)")
                        Button("Save") { save(categoryID: category.id) }
                            .disabled(drafts[category.id] == nil)
                    }
                    if saved > 0 { Text("Current limit: \(Money.formatted(saved))").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .ledgerBackground()
        .navigationTitle("Monthly budgets")
        .modifier(ErrorNotice(message: $error))
    }

    private func save(categoryID: String) {
        guard let draft = drafts[categoryID] else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = text.isEmpty || text.range(of: #"^0(?:\.0{1,2})?$"#, options: .regularExpression) != nil
            ? 0 : (Money.paise(from: text) ?? -1)
        guard amount >= 0 else { error = "Enter a valid INR budget, such as 12000 or 12000.50."; return }
        do {
            try LedgerStore.setBudget(categoryID: categoryID, monthKey: monthKey, amountPaise: amount, in: context)
            drafts[categoryID] = amount > 0 ? Money.input(amount) : ""
        } catch { self.error = error.localizedDescription }
    }

    private func moveMonth(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
        drafts = [:]
    }
}

private struct CSVImportPreviewSheet: View {
    let preview: CSVImportPreview
    let onComplete: (String) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Ready to import") {
                    LabeledContent("New transactions", value: "\(preview.transactions.count)")
                    LabeledContent("Already present", value: "\(preview.duplicateCount)")
                    if preview.restoredDeletedCount > 0 {
                        LabeledContent("Restored from backup", value: "\(preview.restoredDeletedCount)")
                    }
                    LabeledContent("Skipped invalid rows", value: "\(preview.invalidCount)")
                }
                if !preview.examples.isEmpty {
                    Section("Skipped rows") {
                        ForEach(Array(preview.examples.enumerated()), id: \.offset) { _, example in
                            Text(example).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("Transactions and categories will be added to your ledger. Reimporting skips transactions already present. Rows previously deleted from the ledger are restored under new IDs. This restores transactions only; it does not restore merchant rules or budget settings.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review CSV")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importCSV() }.fontWeight(.semibold).disabled(preview.transactions.isEmpty)
                }
            }
            .modifier(ErrorNotice(message: $error))
        }
    }

    private func importCSV() {
        do {
            let result = try CSVBackup.importTransactions(preview, in: context)
            onComplete("Imported \(result.importedCount) transactions. Skipped \(result.duplicateCount) duplicates.")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ShortcutSetupView: View {
    @Environment(\.ledgerPalette) private var palette
    private let steps: [(String, String)] = [
        ("Create a message automation", "Open Apple Shortcuts and create an automation triggered by receiving a Message. Use your bank sender or a message-content filter such as INR."),
        ("Pass the message text", "Add Pocket Ledger’s ‘Import Bank Message’ action. Set Message to the incoming message’s content from Shortcut Input. If needed, add ‘Get Text from Input’ first. Sender is optional."),
        ("Let it run automatically", "Choose the option to run without asking (such as ‘Run Immediately’). Approve any Shortcuts permissions during the first run."),
        ("Cover each bank’s format", "Add matching automations for messages using Rs or ₹ if your banks use those instead of INR. Overlapping rules are okay: duplicate messages are detected."),
        ("Check a real transaction", "Open Pocket Ledger once after installation, then test a real incoming bank message with your phone both unlocked and locked. Check Transactions and Review. You can add ‘Show Notification’ using the action’s result to see why a message was skipped.")
    ]
    var body: some View {
        List {
            Section {
                Label("Bank message → Shortcut → Your ledger", systemImage: "bolt.circle.fill").font(.headline).foregroundStyle(palette.accent)
                Text("iOS keeps your SMS inbox private. You choose which new messages Shortcuts passes to Pocket Ledger. Existing messages are imported by copying and pasting them.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Section {
                    Text(step.1).font(.subheadline)
                } header: { Text("\(index + 1). \(step.0)") }
            }
            Section("What gets saved") {
                Text("Recognized INR purchases, refunds, income, and card repayments are saved. Uncertain details are flagged for review. OTPs, declined payments, and bill reminders are ignored. Unrecognized messages return a reason and are not stored.")
                Text("HDFC, ICICI, and Axis patterns are included. Bank templates vary; if a valid payment is skipped, use manual entry and keep an anonymized example for parser improvements.")
            }.font(.subheadline)
            Section("After restarting your iPhone") { Text("Unlock your phone once so encrypted storage becomes available. Automation timing and execution are controlled by iOS.").font(.subheadline) }
        }.ledgerBackground().navigationTitle("Automatic imports")
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On-device parsing") { Text("Message text is processed in memory. Pocket Ledger stores transaction details and a one-way fingerprint to detect duplicate imports. It does not store the original SMS, OTPs, full account numbers, or full card numbers.") }
            Section("Your private iCloud") { Text("With the iCloud build, transactions, categories, merchant rules, and monthly budgets sync to your private CloudKit database under your Apple Account. There is no Pocket Ledger server, advertising SDK, or analytics service.") }
            Section("Deletion") { Text("Deleted transactions are hidden on all synced devices. A small deletion record remains to prevent an old device or repeated import from restoring them. Exports you saved elsewhere are not deleted by the app.") }
            Section("Automation") { Text("You control message triggers in Apple Shortcuts. Remove those automations to stop automatic imports. Unknown message formats need manual entry; the app does not read your inbox directly.") }
        }.ledgerBackground().navigationTitle("Your privacy")
    }
}
