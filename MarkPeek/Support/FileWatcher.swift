import Foundation

/// Watches one file for writes, renames and deletes (other editors usually
/// save by replacing the file). Events are debounced and delivered on the
/// main actor.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init?(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            pending?.cancel()
            let work = DispatchWorkItem { Task { @MainActor in onChange() } }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}
