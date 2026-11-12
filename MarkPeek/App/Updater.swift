import AppKit
import OSLog
import SwiftUI

/// Checks GitHub Releases for a newer version and installs it in place:
/// download the release zip, swap the bundle in /Applications, relaunch.
/// No third-party framework and no signing key needed.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repository = "turman17/MarkPeek"
    private static let autoCheckKey = "automaticUpdateChecks"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 86_400

    private let log = Logger(subsystem: "com.markpeek.app", category: "updates")
    @Published private(set) var isBusy = false
    @Published var availableRelease: Release?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var automaticallyChecksForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey)
        }
    }

    struct Release: Decodable, Sendable {
        struct Asset: Decodable, Sendable {
            let name: String
            let browserDownloadUrl: String
            enum CodingKeys: String, CodingKey { case name, browserDownloadUrl = "browser_download_url" }
        }
        let tagName: String
        let htmlUrl: String
        let body: String?
        let assets: [Asset]?
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlUrl = "html_url", body, assets }

        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
        var zipURL: URL? { assets?.first { $0.name.hasSuffix(".zip") }.flatMap { URL(string: $0.browserDownloadUrl) } }
        var pageURL: URL? { URL(string: htmlUrl) }
    }

    enum UpdateError: LocalizedError {
        case noArchive, download, extract, install(String)
        var errorDescription: String? {
            switch self {
            case .noArchive: "This release has no installable archive."
            case .download: "The update could not be downloaded."
            case .extract: "The update archive could not be opened."
            case .install(let reason): "The update could not be installed: \(reason)"
            }
        }
    }

    // MARK: Checking

    /// Quiet check at launch, at most once a day, when the user allows it.
    func checkInBackgroundIfDue() {
        guard automaticallyChecksForUpdates else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > Self.checkInterval else { return }
        Task {
            if let release = await fetchNewerRelease() {
                availableRelease = release
                offer(release)
            }
        }
    }

    /// Menu action: always reports the result.
    func checkForUpdates() {
        Task {
            if let release = await fetchNewerRelease() {
                availableRelease = release
                offer(release)
            } else {
                let alert = NSAlert()
                alert.messageText = "You're Up to Date"
                alert.informativeText = "MarkPeek \(currentVersion) is the latest version."
                alert.runModal()
            }
        }
    }

    private func fetchNewerRelease() async -> Release? {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let release = try JSONDecoder().decode(Release.self, from: data)
            return Self.isNewer(release.version, than: currentVersion) ? release : nil
        } catch {
            log.info("update check failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Installing

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "MarkPeek \(release.version) Is Available"
        alert.informativeText = "You have \(currentVersion). The update downloads, installs and relaunches automatically."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertSecondButtonReturn: if let url = release.pageURL { NSWorkspace.shared.open(url) }
        default: break
        }
    }

    func install(_ release: Release) {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.path == "/Applications/MarkPeek.app" else {
            // Not installed in /Applications (a dev build): hand off to the browser.
            if let url = release.zipURL ?? release.pageURL { NSWorkspace.shared.open(url) }
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await replaceBundle(at: bundleURL, with: release)
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
                NSApp.terminate(nil)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Update Failed"
                alert.informativeText = "\(error.localizedDescription)\nYou can download the update in your browser instead."
                alert.addButton(withTitle: "Download in Browser")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn, let url = release.zipURL ?? release.pageURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func replaceBundle(at target: URL, with release: Release) async throws {
        guard let zipURL = release.zipURL else { throw UpdateError.noArchive }
        let (downloaded, response) = try await URLSession.shared.download(from: zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MarkPeekUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let extracted = work.appendingPathComponent("extracted")
        try Self.run("/usr/bin/ditto", ["-x", "-k", downloaded.path, extracted.path], or: .extract)
        guard let newApp = Self.findApp(in: extracted) else { throw UpdateError.extract }
        try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path], or: .extract)

        let backup = work.appendingPathComponent("previous.app")
        do { try FileManager.default.moveItem(at: target, to: backup) }
        catch { throw UpdateError.install("cannot move the current app (\(error.localizedDescription))") }
        do { try FileManager.default.moveItem(at: newApp, to: target) }
        catch {
            try? FileManager.default.moveItem(at: backup, to: target)
            throw UpdateError.install("cannot place the new app (\(error.localizedDescription))")
        }
        log.info("installed update \(release.version, privacy: .public)")
    }

    private static func findApp(in directory: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        for sub in items where sub.hasDirectoryPath { if let app = findApp(in: sub) { return app } }
        return nil
    }

    private static func run(_ path: String, _ arguments: [String], or error: UpdateError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw error }
    }
}
