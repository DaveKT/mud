import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Lighting") {
                    HStack(spacing: 12) {
                        ForEach(Lighting.allCases, id: \.self) { lighting in
                            LightingPreviewCard(
                                lighting: lighting,
                                isSelected: appState.lighting == lighting
                            ) {
                                appState.lighting = lighting
                                appState.saveLighting(lighting)
                            }
                            .frame(width: 72)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle("Readable Column", isOn: Binding(
                    get: { appState.viewToggles.contains(.readableColumn) },
                    set: { _ in appState.toggle(.readableColumn) }
                ))
            }

            Section {
                Toggle("Quit when last window closes", isOn: Binding(
                    get: { appState.quitOnClose },
                    set: { newValue in
                        appState.quitOnClose = newValue
                        appState.saveQuitOnClose()
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
