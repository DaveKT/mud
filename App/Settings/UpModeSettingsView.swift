import SwiftUI

struct UpModeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle("Allow Remote Content", isOn: Binding(
                    get: { appState.allowRemoteContent },
                    set: { newValue in
                        appState.allowRemoteContent = newValue
                        appState.saveAllowRemoteContent()
                    }
                ))
                Text("Load remote images and other external resources referenced in Markdown documents.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
