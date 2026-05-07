import Foundation

struct HarnessLaunchConfiguration {
    let scenario: IslandDebugScenario?
    let presentOverlay: Bool
    let shouldShowControlCenter: Bool
    let shouldStartBridge: Bool
    let shouldPerformBootAnimation: Bool
    let captureDelay: TimeInterval?
    let autoExitAfter: TimeInterval?
    let artifactDirectoryURL: URL?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        scenario = Self.scenarioValue(from: environment["OPEN_ISLAND_HARNESS_SCENARIO"])
        presentOverlay = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_PRESENT_OVERLAY"],
            default: false
        )
        shouldShowControlCenter = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_SHOW_CONTROL_CENTER"],
            default: true
        )
        shouldStartBridge = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_START_BRIDGE"],
            default: true
        )
        shouldPerformBootAnimation = Self.boolValue(
            environment["OPEN_ISLAND_HARNESS_BOOT_ANIMATION"],
            default: true
        )
        captureDelay = Self.timeIntervalValue(
            from: environment["OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS"]
        )
        autoExitAfter = Self.timeIntervalValue(
            from: environment["OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS"]
        )
        artifactDirectoryURL = Self.safeArtifactDirectoryURL(
            from: environment["OPEN_ISLAND_HARNESS_ARTIFACT_DIR"],
            arguments: arguments
        )
    }

    private static func scenarioValue(from rawValue: String?) -> IslandDebugScenario? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return IslandDebugScenario.allCases.first { scenario in
            scenario.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private static func boolValue(_ rawValue: String?, default defaultValue: Bool) -> Bool {
        guard let rawValue else {
            return defaultValue
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return defaultValue
        }

        return switch normalized {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            defaultValue
        }
    }

    private static func timeIntervalValue(from rawValue: String?) -> TimeInterval? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(normalized),
              seconds > 0 else {
            return nil
        }

        return seconds
    }

    /// Default app-owned harness artifact directory under
    /// `~/Library/Application Support/Atoll/harness/`. Used as the
    /// fallback whenever the env-var path is missing or unsafe.
    static var defaultArtifactDirectoryURL: URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("Atoll", isDirectory: true)
            .appendingPathComponent("harness", isDirectory: true)
    }

    /// Resolves and validates the env-var artifact directory.
    ///
    /// `OPEN_ISLAND_HARNESS_ARTIFACT_DIR` is a developer affordance —
    /// the harness runner sets it to a temp dir so screenshots and
    /// JSON reports land somewhere it can scoop them. An attacker who
    /// can poison the user's environment (e.g. via a launchd plist
    /// drop) could otherwise abuse it to plant readable images under
    /// `~/Public/`, `/tmp/$lockfile/`, or any other writable location.
    ///
    /// We refuse the supplied path unless one of:
    /// 1. It resolves under `NSTemporaryDirectory()`
    ///    (`/var/folders/...`).
    /// 2. It resolves under
    ///    `~/Library/Application Support/Atoll/harness/`.
    /// 3. The process was launched with the `--harness` argv flag,
    ///    in which case any writable path is allowed (the harness
    ///    runner is trusted code we ship).
    ///
    /// When refused, we log a warning to stderr and silently fall
    /// back to `defaultArtifactDirectoryURL`. The harness itself
    /// continues — better to capture artifacts in the wrong (but
    /// app-owned) place than to abort the dev run.
    static func safeArtifactDirectoryURL(
        from rawValue: String?,
        arguments: [String]
    ) -> URL? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let candidate = URL(fileURLWithPath: normalized, isDirectory: true)
        let trustedByFlag = arguments.contains("--harness")

        if isPathSafeForHarnessArtifacts(candidate) || trustedByFlag {
            return candidate
        }

        FileHandle.standardError.write(Data(
            "Atoll: refusing OPEN_ISLAND_HARNESS_ARTIFACT_DIR='\(normalized)' — outside allowed roots; falling back to app-owned path.\n".utf8
        ))
        return defaultArtifactDirectoryURL
    }

    /// True if `candidate` lies under an allowed root. Compared on
    /// resolved (symlinks-collapsed) paths so a `/tmp` symlink to
    /// `/var/folders/...` still resolves correctly. Both sides are
    /// canonicalized with `standardizedFileURL.resolvingSymlinksInPath()`.
    static func isPathSafeForHarnessArtifacts(_ candidate: URL) -> Bool {
        let resolvedCandidate = candidate
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let allowedRoots: [String] = [
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath().path,
            defaultArtifactDirectoryURL
                .standardizedFileURL.resolvingSymlinksInPath().path,
        ]
        // Append a trailing slash to the root before doing a prefix
        // match so `/var/folders/abc` does not match `/var/folders/a`.
        let normalizedCandidate = resolvedCandidate.hasSuffix("/")
            ? resolvedCandidate
            : resolvedCandidate + "/"
        for root in allowedRoots {
            let normalizedRoot = root.hasSuffix("/") ? root : root + "/"
            if normalizedCandidate == normalizedRoot
                || normalizedCandidate.hasPrefix(normalizedRoot) {
                return true
            }
        }
        return false
    }
}
