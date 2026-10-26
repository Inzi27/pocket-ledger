import AppIntents
#if canImport(BudgetStore)
import BudgetStore
#endif

struct ImportMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Bank Message"
    static var description = IntentDescription("Save an INR transaction from a bank message. Connect Message Content from your personal message automation. Messages are processed on this device.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Message", description: "The full text of the received bank message.")
    var message: String

    @Parameter(title: "Sender", description: "Optional bank sender identifier.", default: "")
    var sender: String

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$message)") { \.$sender }
    }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try AppRuntime.shared.requireContainer()
        let outcome = try LedgerStore.importMessage(message, sender: sender, in: container.mainContext)
        return .result(value: outcome.message)
    }
}
