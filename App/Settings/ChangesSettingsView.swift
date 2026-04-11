import SwiftUI

struct ChangesSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
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
                #if GIT_PROVIDER
                Toggle(isOn: Binding(
                    get: { appState.showGitWaypoints },
                    set: { newValue in
                        appState.showGitWaypoints = newValue
                        appState.saveShowGitWaypoints()
                    }
                )) {
                    Text("Git commits")
                    Text("Show comparisons against git history in the Changes menu.")
                }
                #endif
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
