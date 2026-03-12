import MudCore
import SwiftUI

struct UpModeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { appState.allowRemoteContent },
                    set: { newValue in
                        appState.allowRemoteContent = newValue
                        appState.saveAllowRemoteContent()
                    }
                )) {
                    Text("Allow Remote Content")
                    Text("Load remote images and other external resources referenced in Markdown documents.")
                }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { appState.enabledExtensions.contains("mermaid") },
                    set: { newValue in
                        if newValue {
                            appState.enabledExtensions.insert("mermaid")
                        } else {
                            appState.enabledExtensions.remove("mermaid")
                        }
                        appState.saveEnabledExtensions()
                    }
                )) {
                    Text("Generate Diagrams")
                    HStack(spacing: 0) {
                        Text("Learn more: ")
                        Button("mermaid-diagrams.md") {
                            SettingsWindowController.shared.window?.close()
                            DocumentController.openBundledDocument(
                                "mermaid-diagrams", subdirectory: "Doc/Examples")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.link)
                    }
                }

            }
            Section("Code Blocks") {
                Toggle(isOn: Binding(
                    get: { appState.viewToggles.contains(.codeHeader) },
                    set: { _ in appState.toggle(.codeHeader) }
                )) {
                    Text("Code Block Headers")
                    Text("Show a header bar with the language name on code blocks.")
                }
                Toggle(isOn: Binding(
                    get: { appState.enabledExtensions.contains("copyCode") },
                    set: { newValue in
                        if newValue {
                            appState.enabledExtensions.insert("copyCode")
                        } else {
                            appState.enabledExtensions.remove("copyCode")
                        }
                        appState.saveEnabledExtensions()
                    }
                )) {
                    Text("Copy Code")
                    Text("Show a Copy button on code blocks.")
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
