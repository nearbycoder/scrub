import AppKit
import Observation
import Security

/// Checks GitHub Releases for a newer version and installs it in place. A download is only
/// installed if it's notarized and signed by the same team as the running app.
@Observable
final class Updater {
    static let shared = Updater()
    static let releasesAPI = URL(string: "https://api.github.com/repos/nearbycoder/scrub/releases/latest")!

    struct Release: Equatable {
        let version: String
        let notes: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum Phase: Equatable {
        case idle, checking, upToDate, available(Release), downloading(Double), installing, failed(String)
    }

    var phase: Phase = .idle
    var showSheet = false
    private let defaults = UserDefaults.standard

    var automaticallyChecks: Bool {
        get { defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoCheckUpdates") }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private init() {}

    /// Called at launch; checks at most once a day and stays quiet unless there's an update.
    func checkInBackgroundIfDue() {
        guard automaticallyChecks, !DemoDirector.isActive else { return }
        let last = defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        Task { await check(userInitiated: false) }
    }

    @MainActor
    func check(userInitiated: Bool) async {
        if userInitiated { phase = .checking; showSheet = true }
        defaults.set(Date(), forKey: "lastUpdateCheck")
        do {
            var request = URLRequest(url: Self.releasesAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
                  let assets = json["assets"] as? [[String: Any]],
                  let zip = assets.first(where: { ($0["name"] as? String) == "Scrub.zip" })?["browser_download_url"] as? String,
                  let zipURL = URL(string: zip) else { throw UpdateError("The release information couldn't be read.") }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let skipped = defaults.string(forKey: "skippedVersion")
            if Self.isNewer(version, than: Self.currentVersion) && (userInitiated || skipped != version) {
                phase = .available(Release(version: version, notes: json["body"] as? String ?? "", downloadURL: zipURL, pageURL: page))
                showSheet = true
            } else if userInitiated {
                phase = .upToDate
            } else {
                phase = .idle
            }
        } catch {
            if userInitiated { phase = .failed(error.localizedDescription) }
        }
    }

    func skip(_ release: Release) {
        defaults.set(release.version, forKey: "skippedVersion")
        showSheet = false
        phase = .idle
    }

    @MainActor
    func install(_ release: Release) async {
        phase = .downloading(0)
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("ScrubUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = try await download(release.downloadURL, to: work.appendingPathComponent("Scrub.zip"))
            phase = .installing
            let unzip = await Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("Scrub.app")
            guard unzip.success, FileManager.default.fileExists(atPath: newApp.path) else { throw UpdateError("The download couldn't be unpacked.") }
            try await Self.verify(newApp)

            let current = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
                throw UpdateError("Scrub can't replace itself in \(current.deletingLastPathComponent().path). Download the update from GitHub instead.")
            }
            try FileManager.default.trashItem(at: current, resultingItemURL: nil)
            try FileManager.default.moveItem(at: newApp, to: current)
            relaunch(current)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL, to destination: URL) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = max(response.expectedContentLength, 1)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let fraction = Double(received) / Double(total)
                await MainActor.run { self.phase = .downloading(fraction) }
            }
        }
        try handle.write(contentsOf: buffer)
        return destination
    }

    /// The new app must pass Gatekeeper and, when the running app is team-signed, come from the same team.
    static func verify(_ app: URL) async throws {
        let assessment = await Shell.run("/usr/sbin/spctl", ["-a", "-t", "exec", app.path])
        guard assessment.success else { throw UpdateError("The update isn't notarized by Apple, so it wasn't installed.") }
        if let expected = teamIdentifier(of: Bundle.main.bundleURL) {
            guard teamIdentifier(of: app) == expected else {
                throw UpdateError("The update isn't signed by the same developer, so it wasn't installed.")
            }
        }
    }

    static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \(Shell.quote(app.path))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
