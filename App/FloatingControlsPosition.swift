enum FloatingControlsPosition: String, CaseIterable {
    case topRight = "topRight"
    case bottomRight = "bottomRight"
    case bottomCenter = "bottomCenter"

    var label: String {
        switch self {
        case .topRight: return "Top right"
        case .bottomRight: return "Bottom right"
        case .bottomCenter: return "Bottom center"
        }
    }
}
