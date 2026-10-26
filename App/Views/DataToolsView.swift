import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(BudgetStore)
import BudgetStore
#endif

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("lastFullBackup") private var lastBackup: Double = 0
    @AppStorage("backupReminderEnabled") private var reminders = false
    @State private var document = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var preview: LedgerBackup?
    @State private var showingPreview = false
    @State private var status: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Button("Create complete backup", systemImage: "square.and.arrow.up") {
                    do { document = BackupDocument(data: try FullBackup.export(in: context)); exporting = true }
                    catch { self.error = error.localizedDescription }
                }
                Button("Restore a backup", systemImage: "square.and.arrow.down") { importing = true }
                if let status { Text(status).font(.subheadline).foregroundStyle(.secondary) }
            } footer: {
                Text("Includes transactions, all categories, merchant rules, budgets, payment nicknames, and import history. Save the file in Files. Appearance and device-lock preferences stay on this iPhone.")
            }
            Section("Backup reminder") {
                if lastBackup > 0 {
                    LabeledContent("Last exported") { Text(Date(timeIntervalSince1970: lastBackup), format: .dateTime.day().month().year().hour().minute()) }
                } else { Text("No complete backup exported from this iPhone yet.").foregroundStyle(.secondary) }
                Toggle("Remind me weekly in the app", isOn: $reminders)
                Text("A reminder appears on Overview when your last export is more than seven days old. A backup file is a snapshot; it does not sync changes between devices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("CSV remains available in Settings for spreadsheets and transaction-only imports. Complete backups contain your financial details, so choose a private location.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Backup & restore").ledgerBackground()
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "PocketLedger-backup-" + Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))) { result in
            switch result {
            case .success: lastBackup = Date.now.timeIntervalSince1970; status = "Complete backup exported."
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50_000_000 else { throw FullBackupError.tooLarge }
                preview = try FullBackup.decode(Data(contentsOf: url))
                showingPreview = true
            } catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: $showingPreview, onDismiss: { preview = nil }) {
            if let preview { BackupPreviewView(backup: preview) { status = $0 } }
        }
        .modifier(ErrorNotice(message: $error))
    }
}

private struct BackupPreviewView: View {
    let backup: LedgerBackup
    let onRestore: (String) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("In this backup") {
                    LabeledContent("Created") { Text(backup.createdAt, format: .dateTime.day().month().year().hour().minute()) }
                    LabeledContent("Transactions", value: "\(backup.entries.count)")
                    LabeledContent("Categories", value: "\(backup.categories.count)")
                    LabeledContent("Merchant rules", value: "\(backup.rules.count)")
                    LabeledContent("Monthly budgets", value: "\(backup.budgets.count)")
                    LabeledContent("Payment nicknames", value: "\(backup.accounts.count)")
                    LabeledContent("Import events", value: "\(backup.activities.count)")
                }
                Section("How restore works") {
                    Text("Missing items are added. Existing transactions and your category, rule, budget, and payment-name edits are kept. Default categories on a fresh installation adopt the backup’s names and appearance.")
                    Text("Transactions you previously deleted can be recovered from this backup. Restoring the same file again skips items already present.")
                }.font(.subheadline)
            }
            .navigationTitle("Review backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") {
                        do { onRestore(try FullBackup.restore(backup, in: context).message); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold)
                }
            }
            .modifier(ErrorNotice(message: $error))
        }
    }
}

struct ImportHistoryView: View {
    @Query private var records: [ImportActivity]
    @Query private var entries: [LedgerEntry]
    @State private var filter = "all"
    @State private var limit = 50
    private var activities: [ImportActivity] { LedgerProjection.activities(records) }
    private var filtered: [ImportActivity] { activities.filter { filter == "all" || $0.status == filter } }
    private var liveEntries: [String: LedgerEntry] { Dictionary(uniqueKeysWithValues: LedgerProjection.entries(entries).map { ($0.id, $0) }) }
    var body: some View {
        let linkedEntries = liveEntries
        List {
            Section {
                if let last = activities.first(where: { $0.origin == "shortcut" }) {
                    LabeledContent("Last Shortcut received") { Text(last.date, format: .dateTime.day().month().hour().minute()) }
                } else { Text("No Shortcut imports recorded yet.") }
                Text("History starts with this update. It records messages that reach Pocket Ledger; it cannot detect a Shortcut that did not run. Original SMS text is never stored.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("\(activities.filter { $0.status == "saved" }.count) saved")
                    Spacer()
                    Text("\(activities.filter { $0.status == "duplicate" }.count) duplicates")
                }.font(.caption)
                Picker("Show", selection: $filter) {
                    Text("All outcomes").tag("all")
                    ForEach(["saved", "duplicate", "ignored", "unrecognized", "failed"], id: \.self) { Text(title($0)).tag($0) }
                }
            }
            Section {
                if filtered.isEmpty {
                    ContentUnavailableView("No import activity", systemImage: "clock.arrow.circlepath",
                                           description: Text("Paste a bank message or run your Shortcut to see its result here."))
                }
                ForEach(Array(filtered.prefix(limit)), id: \.id) { activity in
                    if let entry = linkedEntries[activity.entryID] {
                        NavigationLink { EntryEditor(entry: entry) } label: { row(activity, merchant: entry.merchant) }
                    } else {
                        row(activity, merchant: activity.entryID.isEmpty ? nil : "Transaction no longer available")
                    }
                }
                if filtered.count > limit { Button("Show older activity") { limit += 50 } }
            }
        }
        .navigationTitle("Import activity").ledgerBackground()
        .onChange(of: filter) { _, _ in limit = 50 }
    }
    private func title(_ status: String) -> String {
        switch status {
        case "saved": return "Saved"
        case "duplicate": return "Duplicate"
        case "ignored": return "Skipped"
        case "unrecognized": return "Not recognized"
        default: return "Failed"
        }
    }
    private func row(_ activity: ImportActivity, merchant: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title(activity.status), systemImage: activity.status == "saved" ? "checkmark.circle" : "info.circle")
                    .foregroundStyle(activity.status == "saved" ? Color.green : .secondary)
                Spacer()
                Text(activity.origin == "shortcut" ? "Shortcut" : "Pasted message").foregroundStyle(.secondary)
            }.font(.subheadline)
            if let merchant { Text(merchant).font(.subheadline.weight(.medium)) }
            Text(activity.detail).font(.caption).foregroundStyle(.secondary)
            Text(activity.date, format: .dateTime.day().month().year().hour().minute()).font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}
