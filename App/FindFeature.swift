import Combine
import SwiftUI

// MARK: - Search Types

enum SearchDirection {
    case forward
    case backward
}

enum SearchOrigin {
    case top      // New term: clear selection, scroll to top, find forward
    case refine   // Prefix continuation: collapse selection to start, find forward
    case advance  // Navigation: find from current selection
}

struct MatchInfo: Equatable {
    let current: Int
    let total: Int
}

// MARK: - Search Query

struct SearchQuery: Equatable {
    let id: UUID
    let text: String
    let origin: SearchOrigin
    let direction: SearchDirection
}

// MARK: - Find State

class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var searchText = ""
    @Published private(set) var searchID = UUID()
    @Published private(set) var searchOrigin: SearchOrigin = .top
    @Published private(set) var searchDirection: SearchDirection = .forward
    @Published var matchInfo: MatchInfo?
    private var lastSearchedText = ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        $searchText
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.autoSearch(text)
            }
            .store(in: &cancellables)
    }

    func show() {
        deferMutation { [self] in
            isVisible = true
        }
    }

    func close() {
        deferMutation { [self] in
            isVisible = false
            searchText = ""
            lastSearchedText = ""
            matchInfo = nil
        }
    }

    func clear() {
        searchText = ""
        lastSearchedText = ""
        matchInfo = nil
    }

    func performFind() {
        findNext()
    }

    func findNext() {
        guard !searchText.isEmpty else { return }
        searchDirection = .forward
        searchOrigin = .advance
        lastSearchedText = searchText
        searchID = UUID()
    }

    func findPrevious() {
        guard !searchText.isEmpty else { return }
        searchDirection = .backward
        searchOrigin = .advance
        lastSearchedText = searchText
        searchID = UUID()
    }

    var currentQuery: SearchQuery? {
        guard isVisible, !searchText.isEmpty else { return nil }
        return SearchQuery(
            id: searchID,
            text: searchText,
            origin: searchOrigin,
            direction: searchDirection
        )
    }

    private func autoSearch(_ text: String) {
        guard isVisible, !text.isEmpty else {
            matchInfo = nil
            lastSearchedText = ""
            return
        }
        if text == lastSearchedText { return }
        searchDirection = .forward
        if lastSearchedText.isEmpty || !text.hasPrefix(lastSearchedText) {
            searchOrigin = .top
        } else {
            searchOrigin = .refine
        }
        lastSearchedText = text
        searchID = UUID()
    }

}

// MARK: - Find Match Counter

private struct FindMatchCounter: View {
    let info: MatchInfo

    var body: some View {
        if info.total > 0, info.total <= 999 {
            Text("\(info.current) of \(info.total)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Find Bar Chevron

private struct FindBarChevron<S: PrimitiveButtonStyle>: View {
    let label: String
    let systemImage: String
    let style: S
    let flash: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(style)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .opacity(flash ? 0.5 : 1)
            .disabled(disabled)
    }
}

// MARK: - Find Bar Tahoe Helpers

private extension View {
    @ViewBuilder
    func findBarGlass() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}

// MARK: - Find Bar View

struct FindBar: View {
    @ObservedObject var state: FindState
    var isFocused: FocusState<Bool>.Binding
    @State private var flashDirection: SearchDirection?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.page.badge.magnifyingglass")

                TextField("Find…", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused(isFocused)
                    .onSubmit { state.performFind() }
                    .onKeyPress(.escape) {
                        state.close()
                        return .handled
                    }

                if let info = state.matchInfo {
                    FindMatchCounter(info: info)
                        .transition(.opacity)
                }

                if !state.searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill", action: state.clear)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(6)
            .background(.primary.opacity(0.1), in: ContainerRelativeShape())

            let hasMatches = state.matchInfo.map { $0.total > 0 } ?? false

            FindBarChevron(
                label: "Find Previous", systemImage: "chevron.left",
                style: BorderedButtonStyle(),
                flash: flashDirection == .backward,
                disabled: !hasMatches,
                action: state.findPrevious
            )

            if hasMatches {
                FindBarChevron(
                    label: "Find Next", systemImage: "chevron.right",
                    style: BorderedProminentButtonStyle(),
                    flash: flashDirection == .forward,
                    disabled: false,
                    action: state.findNext
                )
            } else {
                FindBarChevron(
                    label: "Find Next", systemImage: "chevron.right",
                    style: BorderedButtonStyle(),
                    flash: false,
                    disabled: true,
                    action: state.findNext
                )
            }
        }
        .padding(8)
        .frame(maxWidth: 400)
        .containerShape(Capsule())
        .findBarGlass()
        .animation(.easeInOut(duration: 0.15), value: state.searchText.isEmpty)
        .onChange(of: state.searchID) {
            guard state.searchOrigin == .advance else { return }
            withAnimation(.easeIn(duration: 0.1)) {
                flashDirection = state.searchDirection
            } completion: {
                withAnimation(.easeOut(duration: 0.2)) {
                    flashDirection = nil
                }
            }
        }
    }
}

// MARK: - Find Overlay Modifier

struct FindOverlay: ViewModifier {
    @ObservedObject var state: FindState
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if state.isVisible {
                    FindBar(state: state, isFocused: $isFocused)
                        .padding(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: state.isVisible)
            .onChange(of: state.isVisible) { _, isVisible in
                if isVisible { isFocused = true }
            }
    }
}

extension View {
    func findOverlay(state: FindState) -> some View {
        modifier(FindOverlay(state: state))
    }
}
