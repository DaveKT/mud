import Foundation

/// Watches a file for changes using GCD dispatch sources.
///
/// Handles atomic saves (write-to-temp-then-rename) by re-establishing the
/// watch when the file is deleted or renamed. Genuine deletions (where the
/// file does not reappear) are ignored — the document stays open.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        startWatching()
    }

    deinit {
        stopWatching()
    }

    @discardableResult
    private func startWatching() -> Bool {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return false
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            let events = self.source?.data ?? []

            // File was replaced (atomic save) - re-establish watch
            if events.contains(.delete) || events.contains(.rename) {
                self.stopWatching()
                self.reestablishWatch()
            } else {
                self.onChange()
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source?.resume()
        return true
    }

    /// Retry delays for re-establishing the watch after an atomic save.
    /// The file may not yet exist at the path if the editor is slow to land
    /// the replacement. Retries cover slow disks, network mounts, and
    /// Spotlight indexing storms.
    private static let retryDelays: [TimeInterval] = [0.1, 0.3, 1.0]

    private func reestablishWatch(attempt: Int = 0) {
        let delay = Self.retryDelays[attempt]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.startWatching() {
                self.onChange()
            } else if attempt + 1 < Self.retryDelays.count {
                self.reestablishWatch(attempt: attempt + 1)
            }
            // All retries exhausted and file still gone — genuine deletion.
        }
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }
}
