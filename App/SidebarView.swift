import SwiftUI
import MudCore

struct SidebarView: View {
    enum Pane { case outline, changes }

    @State private var pane: Pane = .outline
    @ObservedObject var state: DocumentState
    @ObservedObject var changeTracker: ChangeTracker
    var onSelectHeading: (OutlineHeading) -> Void
    var onSelectChange: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                Text("Outline").tag(Pane.outline)
                Text("Changes").tag(Pane.changes)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Group {
                switch pane {
                case .outline:
                    OutlineSidebarView(state: state, onSelect: onSelectHeading)
                case .changes:
                    ChangesSidebarView(changeTracker: changeTracker,
                                       onSelectChange: onSelectChange)
                }
            }
            .animation(.none, value: pane)
        }
    }
}
