import Foundation
import SwiftData
import SwiftUI
import CloudKit
import CoreData
#if canImport(BudgetStore)
import BudgetStore
#endif
#if os(iOS)
import UIKit
#endif

@MainActor final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()
    @Published var container: ModelContainer?
    @Published var startupError: String?
    @Published var syncStatus = "Stored on this iPhone"
    @Published var lastSync: Date?
    let cloudEnabled: Bool
    let cloudIdentifier: String
    private var observation: NSObjectProtocol?

    private init() {
        cloudEnabled = (Bundle.main.object(forInfoDictionaryKey: "LedgerCloudEnabled") as? String) == "YES"
        cloudIdentifier = Bundle.main.object(forInfoDictionaryKey: "LedgerCloudContainer") as? String ?? ""
        if cloudEnabled {
            syncStatus = "Checking iCloud…"
            observation = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error = event.error { self.syncStatus = "Sync needs attention: \(error.localizedDescription)" }
                    else if event.endDate == nil { self.syncStatus = "Syncing with iCloud…" }
                    else if event.succeeded {
                        self.syncStatus = "iCloud activity completed"
                        self.lastSync = event.endDate
                    }
                }
            }
        }
    }

    func load() {
        guard container == nil else { return }
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PocketLedger", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            #if os(iOS)
            // Background imports can write after the first unlock following a restart.
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: base.path)
            #endif
            if cloudEnabled && (cloudIdentifier.isEmpty || cloudIdentifier.contains("$(")) {
                throw RuntimeError.configuration
            }
            let loaded = try LedgerStore.makeContainer(url: base.appendingPathComponent("Ledger.store"),
                                                       cloudContainer: cloudEnabled ? cloudIdentifier : nil)
            loaded.mainContext.autosaveEnabled = false
            try LedgerStore.seedCategories(in: loaded.mainContext)
            container = loaded
            startupError = nil
            #if os(iOS)
            if cloudEnabled { UIApplication.shared.registerForRemoteNotifications() }
            #endif
        } catch { startupError = error.localizedDescription }
    }

    func requireContainer() throws -> ModelContainer {
        load()
        guard let container else { throw RuntimeError.storage(startupError ?? "Storage could not be opened.") }
        return container
    }

    func checkCloudAccount() async {
        guard cloudEnabled else { return }
        do {
            let status = try await CKContainer(identifier: cloudIdentifier).accountStatus()
            switch status {
            case .available: if lastSync == nil { syncStatus = "iCloud available · waiting for sync activity" }
            case .noAccount: syncStatus = "Sign in to iCloud in iPhone Settings. Your changes are saved locally."
            case .restricted: syncStatus = "iCloud is restricted on this device."
            case .temporarilyUnavailable: syncStatus = "iCloud is temporarily unavailable. Changes are saved locally."
            default: syncStatus = "Could not determine iCloud availability."
            }
        } catch { syncStatus = "Could not check iCloud: \(error.localizedDescription)" }
    }
}

enum RuntimeError: LocalizedError {
    case configuration, storage(String)
    var errorDescription: String? {
        switch self {
        case .configuration: return "The iCloud container identifier is missing from this build."
        case .storage(let message): return message
        }
    }
}
