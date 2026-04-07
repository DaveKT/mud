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

            Section("Change tracking") {
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
                #if GIT_PROVIDER
                Toggle(isOn: Binding(
                    get: { appState.showGitWaypoints },
                    set: { newValue in
                        appState.showGitWaypoints = newValue
                        appState.saveShowGitWaypoints()
                    }
                )) {
                    Text("Git waypoints")
                    Text("Show comparisons against git history in the changes menu.")
                }
                #endif
                Slider(
                    value: Binding(
                        get: { appState.wordDiffThreshold },
                        set: { newValue in
                            appState.wordDiffThreshold = newValue
                            appState.saveWordDiffThreshold()
                        }
                    ),
                    in: 0.0...1.0,
                    step: 0.05
                ) {
                    Text("Word diff threshold")
                    Text("How much can a block change before word highlights are hidden?")
                } minimumValueLabel: {
                    Text("0%")
                } maximumValueLabel: {
                    Text("100%")
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
