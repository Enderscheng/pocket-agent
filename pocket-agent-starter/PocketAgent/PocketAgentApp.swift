import SwiftUI
import AppIntents

@main
struct PocketAgentApp: App {
    init() {
        PocketAgentShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section("1. Test the connection") {
                        Text("Say: Siri, test Pocket Agent")
                        Text("Expected response: Pocket Agent is ready.")
                            .foregroundStyle(.secondary)
                    }
                    Section("2. Test spoken input") {
                        Text("Say: Siri, capture a task with Pocket Agent")
                        Text("When Siri asks what to capture, say: Buy milk tomorrow.")
                        Text("Expected response: Received 3 words. Capture test complete.")
                            .foregroundStyle(.secondary)
                    }
                    Section("3. Repeat while locked") {
                        Text("Enable Siri while locked in Settings. Lock your phone and repeat both tests without looking at Face ID.")
                    }
                    Section("Shortcut registration") {
                        Button("Register Siri shortcuts again") {
                            PocketAgentShortcuts.updateAppShortcutParameters()
                        }
                        Text("You can also find these actions in the Shortcuts app under Pocket Agent.")
                            .foregroundStyle(.secondary)
                    }
                    Section("About this prototype") {
                        Text("This version tests Siri only. It does not save tasks, contact an AI, access your calendar, or write Obsidian notes.")
                        Text("The two test actions request permission to run without unlocking. Siri and iOS still control whether they run on your device.")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Pocket Agent")
            }
        }
    }
}
