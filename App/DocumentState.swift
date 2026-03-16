import Foundation
import Combine
import MudCore

// MARK: - Scroll Target

struct ScrollTarget: Equatable {
    let id: UUID
    let heading: OutlineHeading
}

struct ChangeScrollTarget: Equatable {
    let id: UUID
    let changeIDs: [String]
}

// MARK: - Document State

class DocumentState: ObservableObject {
    @Published var mode: Mode = .up
    @Published var printID: UUID?
    @Published var openInBrowserID: UUID?
    @Published var reloadID: UUID?
    @Published var outlineHeadings: [OutlineHeading] = []
    @Published var scrollTarget: ScrollTarget?
    @Published var changeScrollTarget: ChangeScrollTarget?
    @Published var contentTitle: String?
    let find = FindState()
    let changeTracker = ChangeTracker()

    func toggleMode() {
        mode = mode.toggled()
    }
}
