import AppKit
import Combine
import Foundation

struct UpdateInfo: Equatable {
    let version: String
    let downloadURL: URL?
    let notes: String?
}

/// Checks a small JSON feed for a newer version. The feed URL comes from the
/// `FestiveLightsUpdateURL` Info.plist key, so each build can point at its own
/// release manifest without changing code.
final class UpdateChecker: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case failed(String)
        case notConfigured
    }

    @Published private(set) var state: State = .idle

    private var task: URLSessionDataTask?

    private struct Feed: Decodable {
        let version: String
        let url: String?
        let downloadURL: String?
        let notes: String?
    }

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    var availableUpdate: UpdateInfo? {
        if case .available(let info) = state { return info }
        return nil
    }

    var statusText: String {
        switch state {
        case .idle:
            return feedURL == nil
                ? "Version \(currentVersion) · update feed not configured"
                : "Version \(currentVersion)"
        case .checking:
            return "Checking for updates…"
        case .upToDate:
            return "You're up to date (version \(currentVersion))."
        case .available(let info):
            return "Version \(info.version) is available."
        case .failed(let message):
            return "Couldn't check: \(message)"
        case .notConfigured:
            return "Update feed not configured."
        }
    }

    var feedIsConfigured: Bool {
        feedURL != nil
    }

    func check() {
        guard !isChecking else { return }
        guard let feedURL else {
            state = .notConfigured
            return
        }

        state = .checking
        task?.cancel()

        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 15
        request.setValue("FestiveLights/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handle(data: data, response: response, error: error)
            }
        }
        task?.resume()
    }

    func openDownload() {
        guard let url = availableUpdate?.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func handle(data: Data?, response: URLResponse?, error: Error?) {
        if let error {
            state = .failed(error.localizedDescription)
            return
        }

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            state = .failed("the update server returned an error")
            return
        }

        guard let data else {
            state = .failed("the update feed was empty")
            return
        }

        let feed: Feed
        do {
            feed = try JSONDecoder().decode(Feed.self, from: data)
        } catch {
            state = .failed("the update feed could not be read")
            return
        }

        guard isRemoteVersionNewer(feed.version, than: currentVersion) else {
            state = .upToDate
            return
        }

        let rawURL = feed.url ?? feed.downloadURL
        let download: URL? = {
            guard
                let rawURL,
                let url = URL(string: rawURL),
                let scheme = url.scheme?.lowercased(),
                scheme == "https" || scheme == "http"
            else { return nil }
            return url
        }()

        state = .available(
            UpdateInfo(
                version: feed.version,
                downloadURL: download,
                notes: feed.notes
            )
        )
    }

    private var feedURL: URL? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "FestiveLightsUpdateURL") as? String
        else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    private func isRemoteVersionNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(remoteParts.count, currentParts.count)

        for index in 0..<count {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if remoteValue != currentValue {
                return remoteValue > currentValue
            }
        }
        return false
    }
}
