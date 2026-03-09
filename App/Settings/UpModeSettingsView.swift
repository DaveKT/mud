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
            Section {
                Toggle("Extended DocC Alerts", isOn: Binding(
                    get: { appState.showExtendedAlerts },
                    set: { newValue in
                        appState.showExtendedAlerts = newValue
                        appState.saveShowExtendedAlerts()
                    }
                ))
                Text("Render DocC aliases such as **Remark:**, **Bug:**, and **Experiment:** as styled alerts. When off, they appear as plain blockquotes.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    Text("Learn more: ")
                        .foregroundStyle(.secondary)
                    Button("alerts.md") {
                        SettingsWindowController.shared.window?.close()
                        DocumentController.openBundledDocument(
                            "alerts", subdirectory: "Doc/Examples")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
