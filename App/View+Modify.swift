import SwiftUI

extension View {
    /// Apply a conditional or branching modifier inline without
    /// duplicating the base view.
    @ViewBuilder
    func modify<V: View>(
        @ViewBuilder _ transform: (Self) -> V
    ) -> V {
        transform(self)
    }
}
