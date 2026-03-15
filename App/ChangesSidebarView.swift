import SwiftUI

struct ChangesSidebarView: View {
    var body: some View {
        VStack {
            ContentUnavailableView(
                "No Changes",
                systemImage: "checkmark.circle",
                description: Text("This document has no changes.")
            )
            Spacer()
        }
        .padding(.top, 16)
    }
}
