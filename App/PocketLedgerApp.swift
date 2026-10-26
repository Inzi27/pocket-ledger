import SwiftUI
import SwiftData
import LocalAuthentication
#if canImport(BudgetStore)
import BudgetStore
#endif

@main struct PocketLedgerApp: App {
    @StateObject private var runtime = AppRuntime.shared
    @AppStorage("appThemeColor") private var themeName = AppTheme.teal.rawValue
    @AppStorage("appAppearance") private var appearanceName = AppAppearance.system.rawValue
    private var palette: AppTheme { AppTheme(rawValue: themeName) ?? .teal }
    var body: some Scene {
        WindowGroup {
            Group {
                if let container = runtime.container {
                    LedgerRootView().modelContainer(container)
                } else if let error = runtime.startupError {
                    ContentUnavailableView {
                        Label("Couldn’t open your ledger", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { runtime.load() }
                    }
                } else {
                    ProgressView("Opening your ledger…").task { runtime.load() }
                }
            }
            .environmentObject(runtime)
            .environment(\.ledgerPalette, palette)
            .tint(palette.accent)
            .preferredColorScheme((AppAppearance(rawValue: appearanceName) ?? .system).colorScheme)
        }
    }
}

struct LedgerRootView: View {
    @Environment(\.ledgerPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var lockEnabled = false
    @State private var unlocked = false
    @State private var authenticating = false
    @State private var lockError = ""
    @Query private var records: [LedgerEntry]
    private var reviewCount: Int { LedgerProjection.entries(records).filter(\.needsReview).count }

    var body: some View {
        ZStack {
            TabView {
                NavigationStack { OverviewView() }.tabItem { Label("Overview", systemImage: "chart.pie.fill") }
                NavigationStack { TransactionsView() }.tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                NavigationStack { TransactionsView(reviewOnly: true) }.tabItem { Label("Review", systemImage: "tray.fill") }.badge(reviewCount)
                NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .opacity(lockEnabled && (!unlocked || scenePhase != .active) ? 0 : 1)
            if lockEnabled && (!unlocked || scenePhase != .active) {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 50)).foregroundStyle(palette.accent)
                    Text("Your ledger, just for you").font(.title2.bold())
                    Text(lockError.isEmpty ? "Unlock to see your spending." : lockError).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Unlock Pocket Ledger") { Task { await unlock() } }.buttonStyle(.borderedProminent).disabled(authenticating)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(LedgerTheme.background)
            }
        }
        .task { if lockEnabled { await unlock() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { unlocked = false }
            if phase == .active && lockEnabled && !unlocked { Task { await unlock() } }
        }
        .onChange(of: lockEnabled) { _, enabled in if enabled { unlocked = true } }
    }

    @MainActor private func unlock() async {
        guard !authenticating, scenePhase == .active else { return }
        authenticating = true
        defer { authenticating = false }
        do {
            unlocked = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your expense ledger")
            lockError = ""
        } catch { lockError = "Unlock with Face ID or your device passcode to continue." }
    }
}
