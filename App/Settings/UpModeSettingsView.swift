import MudCore
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
                Toggle("Mermaid Diagrams", isOn: Binding(
                    get: { appState.enabledExtensions.contains("mermaid") },
                    set: { newValue in
                        if newValue {
                            appState.enabledExtensions.insert("mermaid")
                        } else {
                            appState.enabledExtensions.remove("mermaid")
                        }
                        appState.saveEnabledExtensions()
                    }
                ))
                Text("Render mermaid code blocks as diagrams.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
