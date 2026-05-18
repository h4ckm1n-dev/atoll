// GitHubReleaseFetcher.swift
// AtollApp

import Foundation

/// A single release fetched from the GitHub Releases API.
struct GitHubRelease: Sendable {
    /// Raw tag name — e.g. `"v1.1.2-atoll"`.
    let tagName: String
    /// Human-readable release title — e.g. `"Atoll v1.1.2 - Notch Media Player"`.
    let displayName: String
    /// Markdown body of the release notes. May be empty if the release has no notes.
    let body: String
    /// Browser URL to the release page on GitHub.
    let htmlURL: URL
    /// Publication date parsed from the ISO-8601 `published_at` field. `nil` when absent.
    let publishedAt: Date?
}

/// Fetches the latest release from the GitHub Releases API for the Atoll repository.
///
/// This is unauthenticated — the repo is public and 60 req/hr per IP is far more
/// than an hourly update check needs.
actor GitHubReleaseFetcher {
    private let session: URLSession

    private static let endpoint = URL(
        string: "https://api.github.com/repos/h4ckm1n-dev/atoll/releases/latest"
    )!

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the latest release from the GitHub API.
    ///
    /// Returns `nil` on any failure — network error, non-2xx status, or malformed
    /// JSON — so the caller can fall back gracefully to Sparkle's own version string.
    func fetchLatest() async -> GitHubRelease? {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects requests without a User-Agent header.
        request.setValue("Atoll/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String,
            let htmlURLString = json["html_url"] as? String,
            let htmlURL = URL(string: htmlURLString)
        else {
            return nil
        }

        let displayName = (json["name"] as? String) ?? tagName
        let body = (json["body"] as? String) ?? ""
        let publishedAt: Date? = {
            guard let raw = json["published_at"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: raw)
        }()

        return GitHubRelease(
            tagName: tagName,
            displayName: displayName,
            body: body,
            htmlURL: htmlURL,
            publishedAt: publishedAt
        )
    }
}
