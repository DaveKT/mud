import SwiftUI
import MudPreferences

struct DownModeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle("Line numbers", isOn: Binding(
                    get: { appState.viewToggles.contains(.lineNumbers) },
                    set: { _ in appState.toggle(.lineNumbers) }
                ))

                Toggle("Word wrap", isOn: Binding(
                    get: { appState.viewToggles.contains(.wordWrap) },
                    set: { _ in appState.toggle(.wordWrap) }
                ))
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
