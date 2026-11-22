import AppIntents
import Foundation

extension Notification.Name {
    static let pocketVoiceRequested = Notification.Name("PocketAgent.startVoiceChat")
}

struct StartVoiceChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Voice Chat"
    static var description = IntentDescription("Opens Pocket Agent for a Cantonese voice conversation. Unlocking may be required.")
    static var openAppWhenRun: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "startVoiceChat")
        NotificationCenter.default.post(name: .pocketVoiceRequested, object: nil)
        return .result()
    }
}

struct TestConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Test Pocket Agent"
    static var description = IntentDescription("Checks whether Siri can run Pocket Agent without opening it.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Pocket Agent is ready.")
    }
}

struct CaptureTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Test Task Capture"
    static var description = IntentDescription("Tests spoken input. This prototype counts words; it does not save or send them.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Task", requestValueDialog: "What should I capture?")
    var task: String

    static var parameterSummary: some ParameterSummary {
        Summary("Test capture of \(\.$task)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = task.split(whereSeparator: { $0.isWhitespace }).count
        return .result(dialog: "Received \(count) words. Capture test complete.")
    }
}

struct PocketAgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceChatIntent(),
            phrases: ["Start a voice chat with \(.applicationName)", "Talk to \(.applicationName)"],
            shortTitle: "Voice Chat",
            systemImageName: "mic.circle.fill"
        )
        AppShortcut(
            intent: TestConnectionIntent(),
            phrases: ["Test \(.applicationName)"],
            shortTitle: "Test Connection",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: CaptureTaskIntent(),
            phrases: ["Capture a task with \(.applicationName)"],
            shortTitle: "Test Task Capture",
            systemImageName: "waveform"
        )
    }
}
