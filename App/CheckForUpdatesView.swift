#if SPARKLE
import Combine
import Sparkle
import SwiftUI

// MARK: - Sparkle controller

enum SparkleController {
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    static var updater: SPUUpdater { controller.updater }
}

// MARK: - Menu item

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init() {
        SparkleController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @StateObject private var viewModel = CheckForUpdatesViewModel()

    var body: some View {
        Button("Check for Updates...") {
            SparkleController.updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
#endif
