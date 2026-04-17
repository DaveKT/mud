public enum Mode: Sendable {
    case up
    case down

    public func toggled() -> Mode {
        switch self {
        case .up: return .down
        case .down: return .up
        }
    }
}
