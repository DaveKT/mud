import SwiftUI

struct DebuggingSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var showingConfirmation = false
    @State private var didReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Sandbox") {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(isSandboxed ? .green : .red)
                        .font(.system(size: 8))
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { appState.inlineDeletions },
                    set: { newValue in
                        appState.inlineDeletions = newValue
                        appState.saveInlineDeletions()
                    }
                )) {
                    Text("Inline deletions")
                    Text("Show replaced words with strikethrough alongside new words in changed blocks.")
                }
            }

            Section {
                Text("Remove all saved preferences and restore factory defaults. The app will quit so changes take full effect.")
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Reset All Preferences…") {
                        showingConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18)
        .confirmationDialog(
            "Reset all preferences?",
            isPresented: $showingConfirmation
        ) {
            Button("Reset and Quit", role: .destructive) {
                resetAllPreferences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all saved settings and quit the app. Your documents will not be affected.")
        }
    }

    private func resetAllPreferences() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        removeSavedApplicationState(bundleID: bundleID)
        exit(0)
    }

    private func removeSavedApplicationState(bundleID: String) {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        guard let savedStateDir = library?
            .appendingPathComponent("Saved Application State")
            .appendingPathComponent("\(bundleID).savedState")
        else { return }
        try? FileManager.default.removeItem(at: savedStateDir)
    }
}
