import SwiftUI
import SwiftData
#if canImport(BudgetStore)
import BudgetStore
#endif

struct ImportMessageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sender = ""
    @State private var result: ImportOutcome?
    @State private var error: String?
    @State private var showAlert = false
    @State private var manual = false

    var body: some View {
        Form {
            Section {
                Text("Paste a bank message").font(.title2.bold())
                Text("We’ll find the amount, merchant, and payment details. Recognized transactions save immediately.").foregroundStyle(.secondary)
            }.listRowBackground(Color.clear)

            Section {
                TextEditor(text: $message).frame(minHeight: 160).plainTextInput().accessibilityLabel("Bank message text")
                TextField("Sender, if known (optional)", text: $sender).plainTextInput()
            } header: { Text("Transaction message") }
              footer: { Text("Processed on this device. Full message text is never saved or uploaded. For an older message without a date, edit the transaction date after importing.") }

            Section {
                if let result {
                    Text(result.message)
                    if case .unrecognized = result { Button("Add manually") { manual = true } }
                }
            }

            Section { NavigationLink { ShortcutSetupView() } label: { Label("Automate future imports", systemImage: "bolt.fill") } }
        }
        .ledgerBackground().navigationTitle("Import a message")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    guard let outcome = importMessage() else { return }
                    if case .saved = outcome {
                        dismiss()
                    } else {
                        showAlert = true
                    }
                }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onTapGesture {
            #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
        .alert("Import Status", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(result?.message ?? "This transaction has already been imported.")
        }
        .sheet(isPresented: $manual) { NavigationStack { EntryEditor() } }
        .modifier(ErrorNotice(message: $error))
    }

    private func importMessage() -> ImportOutcome? {
        do {
            let outcome = try LedgerStore.importMessage(message, sender: sender, in: context)
            result = outcome
            if case .saved = outcome { message = ""; sender = "" }
            return outcome
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
