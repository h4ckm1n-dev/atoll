# Phase 2 — Custom Theme Registry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
>
> **Execution mode (per user directive):** swarm. Spawn `architect → coder → tester → reviewer` in one Agent message, all `run_in_background: true`, coordinated via `SendMessage`. See "Swarm dispatch" below.

**Goal:** Let users author their own themes outside the app (any text editor, any color tool) and import them as JSON, then manage them through Settings → Appearance: rename, duplicate, export, delete. Built-in flavors stay read-only; custom themes live as one JSON file each under `~/Library/Application Support/Atoll/themes/`.

**Architecture:** Three pieces. (1) `CustomTheme` value type + `ThemePalette: Codable` lock down the JSON schema. (2) `CustomThemeRegistry` actor owns the on-disk directory and exposes load/save/delete/duplicate/import/export. (3) `AppTheme` migrates from a flat `String` enum to an enum-with-associated-value (`.custom(id: UUID)`) — old UserDefaults strings still decode to the matching built-in case. Settings → Appearance gains a "Themes" section with the list + actions; the theme picker grows a "My themes" group below the built-ins.

**Tech Stack:** Swift 6.2 strict concurrency, Foundation `JSONEncoder/Decoder`, `FileManager`, SwiftUI `Form` + `List` + `NSOpenPanel` / `NSSavePanel` for import/export, Swift Testing (`@Test`, `#expect`).

**Authoritative reference:** `docs/plans/2026-05-06-theme-personalization-design.md` — sections "Architecture" (AppTheme reshape, palette propagation), "Data model" (CustomTheme, JSON schema, on-disk layout, registry, import validation), "UI surfaces" (Themes section, picker grouping). The plan does not duplicate; agents read the design doc directly for spec.

---

## Preconditions

1. Latest `main` contains the design supplement commit `7b6395b` (Phase 4 design added) plus all of Phase 1 + the package rename. Run `git log --oneline main -5` to confirm; expect `7b6395b docs: add Phase 4 (frosted panel material)` near the top.
2. Worktree workflow per `CLAUDE.md`. Use `git worktree add ../theme-custom-registry -b feat/theme-custom-registry main`.
3. Dev environment: `swift --version` ≥ 6.2, `xcode-select -p` returns a valid path.
4. `swift build && swift test` from `main` passes (359/359 tests, no warnings beyond pre-existing `@discardableResult` notes).

---

## Swarm dispatch

Spawn all four agents in **one** Agent message:

```javascript
Agent({
  subagent_type: "apple-dev:swift-developer",
  name: "p2-architect",
  run_in_background: true,
  prompt: "Open the theme-custom-registry worktree. Read docs/plans/2026-05-07-phase-2-custom-theme-registry-plan.md section 'Phase A — architect' and the design doc at docs/plans/2026-05-06-theme-personalization-design.md sections 'Architecture' + 'Data model'. Execute Phase A end-to-end. SendMessage to 'p2-coder' on completion with: (a) commit SHA, (b) names of new types exposed (CustomTheme fields, AppTheme cases, registry public surface), (c) any deviations. Then exit."
})
Agent({
  subagent_type: "apple-dev:swift-developer",
  name: "p2-coder",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p2-architect'. Read plan section 'Phase B — coder' and the design doc's 'UI surfaces' section. Execute Phase B end-to-end. SendMessage to 'p2-tester' with: (a) commit SHA, (b) per-file change summary, (c) localized string keys added. Then exit."
})
Agent({
  subagent_type: "apple-dev:swift-developer",
  name: "p2-tester",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p2-coder'. Read plan section 'Phase C — tester'. Execute Phase C end-to-end. When all tests pass (target: 359 + ~12 new = ~371), SendMessage to 'p2-reviewer' with full test output tail. Then exit."
})
Agent({
  subagent_type: "pr-review-toolkit:code-reviewer",
  name: "p2-reviewer",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p2-tester'. Read plan section 'Phase D — reviewer'. Execute Phase D end-to-end (CPU smoke + manual JSON import + PR creation). Report final status to user with PR URL."
})

SendMessage({ to: "p2-architect", summary: "Start", message: "Phase 2 of theme personalization. Plan at docs/plans/2026-05-07-phase-2-custom-theme-registry-plan.md. Worktree feat/theme-custom-registry off main. Begin Phase A." })
```

**Coordination rules:**
- All four agents work in the SAME worktree (sequential pipeline, not parallel writes).
- One atomic commit per phase.
- An agent that hits a blocker `SendMessage`s back to the dispatcher (parent session) and exits — does NOT loop.
- The dispatcher (you) does not poll. Agents message back when done.

---

## Phase A — architect

**Owner:** `p2-architect` agent.
**Goal:** Lock the data model. Land `CustomTheme`, the JSON schema for `ThemePalette`, the `AppTheme` enum migration with backwards-compat decoding, and the `CustomThemeRegistry` actor — without any UI or registry-loading-at-startup yet. After Phase A the codebase has all the types in place + their unit tests, but no settings UI uses them.

### Task A.1: Branch + worktree setup

**Step A.1.1: Verify branch + clean tree**

```bash
git rev-parse --abbrev-ref HEAD
# Expected: feat/theme-custom-registry
git status -sb
# Expected: ## feat/theme-custom-registry (no changes)
```

**Step A.1.2: Verify the design doc and Phase 1 work are present**

```bash
test -f docs/plans/2026-05-06-theme-personalization-design.md && echo OK
ls Sources/AtollCore/Theme.swift && grep -q "PaletteRole" Sources/AtollCore/Theme.swift && echo "Phase 1 OK"
# Expected: both echoes
```

If anything missing, abort and `SendMessage` to dispatcher.

### Task A.2: Make `ThemePalette` Codable

**Files:** Modify `Sources/AtollCore/Theme.swift`.

**Step A.2.1: Read the current `ThemePalette` definition**

```bash
grep -n "public struct ThemePalette\|public var.*: ProjectColor\|public var isLight" Sources/AtollCore/Theme.swift | head -30
```

Confirm the 26 stored properties are all `public var <name>: ProjectColor` plus `public var isLight: Bool`.

**Step A.2.2: Append a `Codable` conformance + custom Coding keys**

After the existing `ThemePalette.from(hex:)` static method (around line 130), append:

```swift
extension ThemePalette: Codable {
    /// Schema version of the on-disk JSON. Bump when the field set
    /// changes incompatibly. Decoder rejects files with a version
    /// higher than `currentSchemaVersion` (forward-incompatible).
    public static let currentSchemaVersion: Int = 1

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isLight
        case base, mantle, crust
        case surface0, surface1, surface2
        case text, subtext1, subtext0
        case overlay2, overlay1, overlay0
        case rosewater, flamingo, pink, mauve
        case red, maroon, peach, yellow
        case green, teal, sky, sapphire
        case blue, lavender
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Theme schemaVersion \(version) is newer than supported (\(Self.currentSchemaVersion)). Update Atoll."
            ))
        }
        func hex(_ key: CodingKeys) throws -> ProjectColor {
            let raw = try c.decode(String.self, forKey: key)
            guard ThemePalette.isValidHex(raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Invalid hex value '\(raw)' for color '\(key.stringValue)'. Expected 6 hex chars."
                ))
            }
            return ProjectColor.fromHex(raw)
        }
        self.init(
            base: try hex(.base), mantle: try hex(.mantle), crust: try hex(.crust),
            surface0: try hex(.surface0), surface1: try hex(.surface1), surface2: try hex(.surface2),
            text: try hex(.text), subtext1: try hex(.subtext1), subtext0: try hex(.subtext0),
            overlay2: try hex(.overlay2), overlay1: try hex(.overlay1), overlay0: try hex(.overlay0),
            rosewater: try hex(.rosewater), flamingo: try hex(.flamingo), pink: try hex(.pink), mauve: try hex(.mauve),
            red: try hex(.red), maroon: try hex(.maroon), peach: try hex(.peach), yellow: try hex(.yellow),
            green: try hex(.green), teal: try hex(.teal), sky: try hex(.sky), sapphire: try hex(.sapphire),
            blue: try hex(.blue), lavender: try hex(.lavender),
            isLight: try c.decode(Bool.self, forKey: .isLight)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(isLight, forKey: .isLight)
        try c.encode(base.toHex(), forKey: .base)
        try c.encode(mantle.toHex(), forKey: .mantle)
        try c.encode(crust.toHex(), forKey: .crust)
        try c.encode(surface0.toHex(), forKey: .surface0)
        try c.encode(surface1.toHex(), forKey: .surface1)
        try c.encode(surface2.toHex(), forKey: .surface2)
        try c.encode(text.toHex(), forKey: .text)
        try c.encode(subtext1.toHex(), forKey: .subtext1)
        try c.encode(subtext0.toHex(), forKey: .subtext0)
        try c.encode(overlay2.toHex(), forKey: .overlay2)
        try c.encode(overlay1.toHex(), forKey: .overlay1)
        try c.encode(overlay0.toHex(), forKey: .overlay0)
        try c.encode(rosewater.toHex(), forKey: .rosewater)
        try c.encode(flamingo.toHex(), forKey: .flamingo)
        try c.encode(pink.toHex(), forKey: .pink)
        try c.encode(mauve.toHex(), forKey: .mauve)
        try c.encode(red.toHex(), forKey: .red)
        try c.encode(maroon.toHex(), forKey: .maroon)
        try c.encode(peach.toHex(), forKey: .peach)
        try c.encode(yellow.toHex(), forKey: .yellow)
        try c.encode(green.toHex(), forKey: .green)
        try c.encode(teal.toHex(), forKey: .teal)
        try c.encode(sky.toHex(), forKey: .sky)
        try c.encode(sapphire.toHex(), forKey: .sapphire)
        try c.encode(blue.toHex(), forKey: .blue)
        try c.encode(lavender.toHex(), forKey: .lavender)
    }

    /// Validates a 6-char hex string (no `#` prefix). Used by the
    /// decoder to reject malformed import files cleanly.
    public static func isValidHex(_ raw: String) -> Bool {
        var s = raw
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return false }
        return s.allSatisfy { $0.isHexDigit }
    }
}

extension ProjectColor {
    /// Encodes this color as a 6-char lowercase hex string (no '#').
    public func toHex() -> String {
        let r = Int((red * 255).rounded()) & 0xff
        let g = Int((green * 255).rounded()) & 0xff
        let b = Int((blue * 255).rounded()) & 0xff
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
```

**Step A.2.3: Verify build**

```bash
swift build 2>&1 | tail -3
# Expected: Build complete!
```

### Task A.3: Migrate `AppTheme` to enum-with-associated-value

**Files:** Modify `Sources/AtollCore/Theme.swift`.

**Step A.3.1: Read the current AppTheme definition**

```bash
grep -nA 20 "public enum AppTheme" Sources/AtollCore/Theme.swift | head -40
```

Confirm it's currently `enum AppTheme: String, Codable, CaseIterable, Sendable` with 5 cases.

**Step A.3.2: Replace the `AppTheme` definition + extend resolution**

Replace the existing enum block:

```swift
public enum AppTheme: Sendable, Hashable {
    case system
    case latte
    case frappe
    case macchiato
    case mocha
    /// Custom theme stored in `CustomThemeRegistry`. The `id` resolves
    /// to a `CustomTheme` whose palette is rendered. If the id is
    /// missing from the registry (file deleted out-of-band), the
    /// theme manager falls back to `.mocha`.
    case custom(id: UUID)

    /// Built-in flavors that ship with the app. Custom themes are not
    /// listed here — they're enumerated separately via the registry.
    public static let builtIn: [AppTheme] = [.system, .latte, .frappe, .macchiato, .mocha]

    public var displayName: String {
        switch self {
        case .system:    return "System"
        case .latte:     return "Catppuccin Latte"
        case .frappe:    return "Catppuccin Frappé"
        case .macchiato: return "Catppuccin Macchiato"
        case .mocha:     return "Catppuccin Mocha"
        case .custom:    return "Custom"  // overridden at the call site with the CustomTheme.displayName
        }
    }

    /// Stable identifier used for `Picker.tag(_:)` and persistence.
    /// Built-ins use a kind keyword; custom themes use their UUID.
    public var stableID: String {
        switch self {
        case .system:    return "system"
        case .latte:     return "latte"
        case .frappe:    return "frappe"
        case .macchiato: return "macchiato"
        case .mocha:     return "mocha"
        case .custom(let id): return "custom:\(id.uuidString)"
        }
    }

    /// Reverse of `stableID`. Used when reading the persisted theme
    /// choice back from UserDefaults. Returns nil for unrecognized.
    public init?(stableID: String) {
        switch stableID {
        case "system":    self = .system
        case "latte":     self = .latte
        case "frappe":    self = .frappe
        case "macchiato": self = .macchiato
        case "mocha":     self = .mocha
        // Backwards-compat with old persisted strings from before
        // the Atoll rebrand.
        case "catppuccinLatte":     self = .latte
        case "catppuccinFrappe":    self = .frappe
        case "catppuccinMacchiato": self = .macchiato
        case "catppuccinMocha":     self = .mocha
        default:
            guard stableID.hasPrefix("custom:"),
                  let id = UUID(uuidString: String(stableID.dropFirst("custom:".count))) else {
                return nil
            }
            self = .custom(id: id)
        }
    }
}

extension AppTheme: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, id
    }

    public init(from decoder: Decoder) throws {
        // Permit both the new keyed shape ({"kind":"mocha"} or
        // {"kind":"custom","id":"..."}) and the legacy unkeyed
        // single-string shape ("catppuccinMocha", etc.).
        if let single = try? decoder.singleValueContainer().decode(String.self),
           let theme = AppTheme(stableID: single) {
            self = theme
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "system":    self = .system
        case "latte":     self = .latte
        case "frappe":    self = .frappe
        case "macchiato": self = .macchiato
        case "mocha":     self = .mocha
        case "custom":
            self = .custom(id: try c.decode(UUID.self, forKey: .id))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "Unknown AppTheme kind '\(kind)'"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system:    try c.encode("system",    forKey: .kind)
        case .latte:     try c.encode("latte",     forKey: .kind)
        case .frappe:    try c.encode("frappe",    forKey: .kind)
        case .macchiato: try c.encode("macchiato", forKey: .kind)
        case .mocha:     try c.encode("mocha",     forKey: .kind)
        case .custom(let id):
            try c.encode("custom", forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }
}
```

**Step A.3.3: Update the `palette` resolution extension**

The existing extension `extension AppTheme { public var palette: ThemePalette { ... } }` references the old enum cases. It now needs to handle `.custom` — but `.custom` requires a registry lookup, which lives in `ThemeManager`, not `AppTheme`. Refactor the built-in resolution into a separate helper:

Replace the existing `extension AppTheme { public var palette: ThemePalette { ... } }` with:

```swift
extension AppTheme {
    /// Resolves the palette for a *built-in* theme. Returns nil for
    /// `.custom` — the caller (typically `ThemeManager`) is responsible
    /// for looking that up in `CustomThemeRegistry`.
    public var builtInPalette: ThemePalette? {
        switch self {
        case .system:    return .system
        case .latte:     return .latte
        case .frappe:    return .frappe
        case .macchiato: return .macchiato
        case .mocha:     return .mocha
        case .custom:    return nil
        }
    }
}
```

**Step A.3.4: Update everywhere that previously called `theme.palette`**

```bash
grep -rn "\\.palette\b" Sources/ Tests/ 2>/dev/null | grep -v "themePalette\|themeManager\|previewPalette" | head -20
```

For built-in-only call sites in `Sources/AtollApp/ThemeManager.swift` and tests, change `theme.palette` → `theme.builtInPalette ?? .mocha`. The `ThemeManager` will do the proper resolution in Phase B; for now just keep things compiling. Specifically:

- `Tests/AtollCoreTests/ThemeTests.swift` — anywhere `.palette` is called on an `AppTheme.allCases` element, replace with `theme.builtInPalette ?? .mocha`. This works because `AppTheme.builtIn` (not `.allCases` since `.custom` has an associated value and can't be in `allCases`) iterates only the 5 built-ins, all of which return non-nil.

⚠ **`AppTheme: CaseIterable` was removed** when we added the associated-value case (compiler can't synthesize it for cases with associated values). Tests that use `AppTheme.allCases` must change to `AppTheme.builtIn`.

```bash
grep -rn "AppTheme\.allCases" Sources/ Tests/ 2>/dev/null | head
```

For each match: change `AppTheme.allCases` → `AppTheme.builtIn`.

**Step A.3.5: Build + run existing tests**

```bash
swift build 2>&1 | tail -3
# Expected: Build complete!
swift test 2>&1 | tail -3
# Expected: Test run with 359 tests in 41 suites passed (or close to it; some
# tests may need the .builtIn rename — fix them in this same task)
```

If any test fails because of the migration, fix them inline (the test file may need its `.allCases` → `.builtIn` rename and/or the `AppTheme(rawValue:)` → `AppTheme(stableID:)` rename).

### Task A.4: Add `CustomTheme` value type

**Files:** Create `Sources/AtollCore/CustomTheme.swift`.

**Step A.4.1: Write the file**

```swift
import Foundation

/// A user-authored theme. Stored as one JSON file per theme under
/// `~/Library/Application Support/Atoll/themes/<id>.json`.
///
/// The `palette` field carries the same 26-color taxonomy as the
/// built-in flavors (Catppuccin convention). `basedOn` records which
/// built-in preset the user forked from — used purely for display
/// ("forked from Mocha") and for the editor's "Reset to base" action
/// in Phase 3. The `basedOn` field is informational; changing the
/// palette does not retroactively update `basedOn`.
public struct CustomTheme: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var palette: ThemePalette
    public var basedOn: AppTheme
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        palette: ThemePalette,
        basedOn: AppTheme,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.palette = palette
        self.basedOn = basedOn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convenience: derive a fresh `CustomTheme` from a built-in
    /// preset. Used by the "Create from preset…" button in Settings
    /// (Phase 2 ships a duplicate-only flow; Phase 3 opens the editor
    /// pre-populated with the result of this call).
    public static func fork(from preset: AppTheme, displayName: String, now: Date = Date()) -> CustomTheme {
        let palette = preset.builtInPalette ?? .mocha
        return CustomTheme(
            displayName: displayName,
            palette: palette,
            basedOn: preset,
            createdAt: now,
            updatedAt: now
        )
    }
}
```

**Step A.4.2: Build**

```bash
swift build 2>&1 | tail -3
```

### Task A.5: Add `CustomThemeRegistry` actor

**Files:** Create `Sources/AtollCore/CustomThemeRegistry.swift`.

**Step A.5.1: Write the file**

```swift
import Foundation

/// Errors thrown by `CustomThemeRegistry` for IO and import failures.
/// Localized messages are intentionally English-only at the model
/// layer — the UI catches these and maps to localized strings via
/// `LanguageManager`.
public enum ThemeRegistryError: Error, LocalizedError, Equatable {
    case directoryUnavailable(URL)
    case malformedJSON(url: URL, underlying: String)
    case missingField(url: URL, field: String)
    case ioFailure(url: URL, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let url):
            return "Themes directory is unavailable: \(url.path)"
        case .malformedJSON(let url, let underlying):
            return "Theme file is malformed: \(url.lastPathComponent) — \(underlying)"
        case .missingField(let url, let field):
            return "Theme file is missing the `\(field)` color: \(url.lastPathComponent)"
        case .ioFailure(let url, let underlying):
            return "Theme file IO failed: \(url.lastPathComponent) — \(underlying)"
        }
    }
}

/// Owns the on-disk directory of user-authored themes. One file per
/// theme keyed by UUID — atomic writes, drag-from-Finder shareability,
/// no special characters in filenames.
///
/// Actor isolation: serializes all file IO. Public methods are async;
/// the SwiftUI layer awaits them from MainActor without contention.
public actor CustomThemeRegistry {
    /// In-memory cache of loaded themes, sorted by `createdAt` ascending
    /// (oldest first) so the UI list order is stable across launches.
    public private(set) var themes: [CustomTheme] = []

    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Default location: `~/Library/Application Support/Atoll/themes/`.
    /// Tests inject a temp directory for isolation.
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Atoll", isDirectory: true)
            .appendingPathComponent("themes", isDirectory: true)
    }

    /// Scans the directory and populates `themes`. Safe to call on
    /// startup. Per-file decode errors are *swallowed* (logged via
    /// stderr) rather than propagated — one corrupt file should not
    /// hide the rest of the user's library.
    public func load() async throws {
        try ensureDirectoryExists()
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        )) ?? []
        var loaded: [CustomTheme] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                let theme = try decoder.decode(CustomTheme.self, from: data)
                loaded.append(theme)
            } catch {
                FileHandle.standardError.write(
                    Data("Atoll: skipping corrupt theme \(url.lastPathComponent): \(error)\n".utf8)
                )
            }
        }
        themes = loaded.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ theme: CustomTheme) async throws {
        try ensureDirectoryExists()
        var updated = theme
        updated.updatedAt = Date()
        let url = fileURL(for: updated.id)
        do {
            let data = try encoder.encode(updated)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
        if let index = themes.firstIndex(where: { $0.id == updated.id }) {
            themes[index] = updated
        } else {
            themes.append(updated)
            themes.sort { $0.createdAt < $1.createdAt }
        }
    }

    public func delete(id: UUID) async throws {
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
            }
        }
        themes.removeAll { $0.id == id }
    }

    public func duplicate(id: UUID) async throws -> CustomTheme {
        guard let source = themes.first(where: { $0.id == id }) else {
            throw ThemeRegistryError.ioFailure(
                url: fileURL(for: id),
                underlying: "Theme \(id) not found in registry"
            )
        }
        let copy = CustomTheme(
            displayName: nextAvailableDuplicateName(for: source.displayName),
            palette: source.palette,
            basedOn: source.basedOn
        )
        try await save(copy)
        return copy
    }

    /// Imports a theme from an external JSON file. The file's id is
    /// REPLACED with a fresh UUID so two users importing the same
    /// shared theme don't collide if the original is later imported
    /// from a friend. Returns the imported theme so the caller can
    /// flip the picker to it.
    public func importTheme(from url: URL) async throws -> CustomTheme {
        try ensureDirectoryExists()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
        let decoded: CustomTheme
        do {
            decoded = try decoder.decode(CustomTheme.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ThemeRegistryError.missingField(url: url, field: key.stringValue)
        } catch {
            throw ThemeRegistryError.malformedJSON(url: url, underlying: "\(error)")
        }
        var fresh = decoded
        // Replace the id so re-imports of the same shared file each
        // produce their own entry in the user's library.
        let renamed = CustomTheme(
            id: UUID(),
            displayName: decoded.displayName,
            palette: fresh.palette,
            basedOn: fresh.basedOn,
            createdAt: Date(),
            updatedAt: Date()
        )
        _ = fresh
        try await save(renamed)
        return renamed
    }

    public func exportTheme(_ theme: CustomTheme, to url: URL) async throws {
        do {
            let data = try encoder.encode(theme)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
    }

    // MARK: - Internal helpers

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        if fileManager.fileExists(atPath: directory.path) { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ThemeRegistryError.directoryUnavailable(directory)
        }
    }

    /// Picks "<base> copy", "<base> copy 2", "<base> copy 3" … Used by
    /// `duplicate(id:)` so the user sees a unique name in the list
    /// without manual renaming.
    private func nextAvailableDuplicateName(for base: String) -> String {
        let stem = "\(base) copy"
        if !themes.contains(where: { $0.displayName == stem }) { return stem }
        var index = 2
        while themes.contains(where: { $0.displayName == "\(stem) \(index)" }) {
            index += 1
        }
        return "\(stem) \(index)"
    }
}
```

**Step A.5.2: Build**

```bash
swift build 2>&1 | tail -3
# Expected: Build complete!
```

### Task A.6: Wire Phase A into ThemeManager (resolution only — UI stays Phase B)

**Files:** Modify `Sources/AtollApp/ThemeManager.swift`.

**Step A.6.1: Read the current ThemeManager**

```bash
cat Sources/AtollApp/ThemeManager.swift | head -80
```

**Step A.6.2: Extend it**

Add the registry as a stored property and update the palette resolution to consult it:

```swift
// At the top of the existing class:
public private(set) var customRegistry: CustomThemeRegistry

// In the existing init, append after `self.theme = ...`:
self.customRegistry = CustomThemeRegistry()

// Replace the existing `public var palette: ThemePalette { theme.palette }`
// (or whatever it currently says — adjust the previous Phase A1 change here):
public var palette: ThemePalette {
    if let preview = previewPalette { return preview }  // see note below
    if case .custom(let id) = theme {
        // Custom resolution requires the registry's cached themes.
        // The cache is populated by `loadCustomThemes()` on app start;
        // until then `.custom` falls back to mocha.
        if let custom = customThemeCache[id] { return custom.palette }
        return .mocha
    }
    return theme.builtInPalette ?? .mocha
}

// previewPalette is added in Phase 3 (editor). Stub it here as nil so
// Phase 2 compiles cleanly without the editor.
public var previewPalette: ThemePalette? = nil

// Add an in-memory mirror of the actor's themes so `palette` (a
// synchronous getter on @Observable @MainActor) doesn't need to
// `await`. The mirror is refreshed via `loadCustomThemes()` and after
// every save/delete via `refreshCustomThemes()`.
private var customThemeCache: [UUID: CustomTheme] = [:]

public func loadCustomThemes() async {
    do {
        try await customRegistry.load()
    } catch {
        // Registry IO errors should not crash the app — log and keep
        // going with an empty library.
        FileHandle.standardError.write(
            Data("Atoll: failed to load custom themes: \(error)\n".utf8)
        )
    }
    await refreshCustomThemes()
}

public func refreshCustomThemes() async {
    let themes = await customRegistry.themes
    customThemeCache = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })
}

/// All custom themes, in the order the picker should display them
/// (oldest first — matches creation order, stable across launches).
public var customThemes: [CustomTheme] {
    Array(customThemeCache.values).sorted { $0.createdAt < $1.createdAt }
}
```

**Step A.6.3: Trigger registry load on app start**

Find where `ThemeManager` is instantiated (likely `OpenIslandApp.swift` `@State private var model = AppModel()` or similar). Add a call to `loadCustomThemes()` from app init or `.task` modifier. Specifically in `Sources/AtollApp/OpenIslandApp.swift`:

```swift
// In the App struct's body, on the root scene's content view:
.task {
    await appDelegate.model.themeManager.loadCustomThemes()
}
```

Find the exact site by:
```bash
grep -n "themeManager\|ThemeManager()" Sources/AtollApp/AppModel.swift Sources/AtollApp/OpenIslandApp.swift
```

If `.task` doesn't fit cleanly there, fire-and-forget from the existing `OpenIslandAppDelegate.applicationDidFinishLaunching`:

```swift
Task { await self.model.themeManager.loadCustomThemes() }
```

**Step A.6.4: Build + run existing tests**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -3
# Expected: 359/359 tests still passing
```

### Task A.7: Commit Phase A

```bash
git add Sources/AtollCore/Theme.swift \
        Sources/AtollCore/CustomTheme.swift \
        Sources/AtollCore/CustomThemeRegistry.swift \
        Sources/AtollApp/ThemeManager.swift \
        Sources/AtollApp/OpenIslandApp.swift \
        Tests/AtollCoreTests/ThemeTests.swift  # if any test files needed updates

git commit -m "$(cat <<'EOF'
feat(theme): Phase 2A — CustomTheme model + CustomThemeRegistry actor + AppTheme migration

Phase A of the custom theme registry. Lays the data model;
no Settings UI yet (Phase B).

- ThemePalette now Codable. Flat-hex JSON shape with schemaVersion
  (currently 1) + isLight + 26 hex strings keyed by role. Decoder
  validates each hex via ThemePalette.isValidHex and throws
  DecodingError on malformed input. Encoder emits sorted-keys
  pretty-printed JSON for diff-friendly storage.
- AppTheme migrated from `enum: String` to enum-with-associated-value:
  .system, .latte, .frappe, .macchiato, .mocha, .custom(id: UUID).
  Custom Codable conformance accepts both the new keyed shape
  ({"kind":"mocha"} / {"kind":"custom","id":"..."}) and the legacy
  unkeyed-string shape ("catppuccinMocha" etc.) for backwards-compat
  with users upgrading from pre-fork builds.
- AppTheme.allCases removed (associated-value cases can't synthesize
  CaseIterable). Replaced with `AppTheme.builtIn` for the 5 built-ins.
  Tests updated.
- AppTheme.builtInPalette returns nil for .custom — the registry
  layer is responsible for resolving custom palettes.
- New CustomTheme value type (Identifiable, Codable, Equatable,
  Sendable). Fields: id, displayName, palette, basedOn, createdAt,
  updatedAt. CustomTheme.fork(from:displayName:) convenience.
- New CustomThemeRegistry actor:
  - One file per theme under ~/Library/Application Support/Atoll/themes/
  - load(): scans directory, skips corrupt files with stderr log
  - save / delete / duplicate / importTheme(from:) / exportTheme(_:to:)
  - duplicate() picks "<base> copy", "<base> copy 2", … unique names
  - importTheme replaces the source id with a fresh UUID so two users
    importing the same shared file don't collide
- ThemeManager exposes `customRegistry` + `customThemes` + `loadCustomThemes()`.
  Synchronous palette getter consults a MainActor-isolated cache
  (refreshCustomThemes() syncs from the actor) so views can read the
  palette without awaiting.
- App start triggers `await loadCustomThemes()` once.

All 359 existing tests still green.
EOF
)"
```

```bash
git show --stat HEAD
# Expected: ~5-6 files changed, ~400-500 insertions
```

### Task A.8: Hand off to coder

`SendMessage` to `'p2-coder'`:

> Phase A complete at commit `<sha>`.
>
> Exposed:
> - `CustomTheme` (id, displayName, palette, basedOn, createdAt, updatedAt) + `.fork(from:displayName:)`
> - `ThemeRegistryError` (4 cases — directoryUnavailable, malformedJSON, missingField, ioFailure)
> - `CustomThemeRegistry` actor (themes, load, save, delete, duplicate, importTheme, exportTheme)
> - `AppTheme.custom(id: UUID)` + `.builtIn` static + `.stableID` + `.init(stableID:)`
> - `ThemeManager.customRegistry`, `.customThemes`, `.loadCustomThemes()`, `.refreshCustomThemes()`
> - `ThemePalette: Codable` (schemaVersion: 1, flat hex dict)
>
> All 359 tests green; build clean. Begin Phase B — Settings UI.

Then exit. Do not start Phase B yourself.

---

## Phase B — coder

**Owner:** `p2-coder` agent.
**Goal:** Wire the registry into Settings → Appearance with the "Themes" section + import/export + theme picker grouping. After Phase B the user can: see custom themes in the picker, import a hand-written JSON file, see it appear in the list + picker, switch to it, restart the app and see it persist; rename, duplicate, delete it from the list; export it back to a JSON file.

### Task B.1: Read the design doc's "UI surfaces" section

```bash
sed -n '/^## UI surfaces$/,/^## Color mapping/p' docs/plans/2026-05-06-theme-personalization-design.md | head -80
```

Specifically the layout sketch + the picker grouping. Phase B implements the **library list** (rename / duplicate / delete / import / export / "+ Create from preset…") but NOT the editor sheet (that's Phase 3).

### Task B.2: Add the theme picker grouping

**Files:** Modify `Sources/AtollApp/Views/AppearanceSettingsPane.swift`.

**Step B.2.1: Find the current theme picker**

```bash
grep -nB2 -A8 "settings\.theme\.picker\|\\bPicker(.*theme" Sources/AtollApp/Views/AppearanceSettingsPane.swift | head -25
```

**Step B.2.2: Replace it with a grouped picker**

The existing picker likely uses `ForEach(AppTheme.allCases)` or similar. Replace with two `Section`s — one for built-ins, one for custom themes:

```swift
Picker(lang.t("settings.theme.picker"), selection: themeBinding) {
    Section(lang.t("settings.theme.builtin")) {
        ForEach(AppTheme.builtIn, id: \.stableID) { theme in
            Text(theme.displayName).tag(theme.stableID)
        }
    }
    if !model.themeManager.customThemes.isEmpty {
        Section(lang.t("settings.theme.custom")) {
            ForEach(model.themeManager.customThemes) { custom in
                Text(custom.displayName).tag(AppTheme.custom(id: custom.id).stableID)
            }
        }
    }
}
```

Where `themeBinding` is a `Binding<String>` that bridges between `AppTheme.stableID` and `model.themeManager.theme` (set/get). Add it as a private `var themeBinding: Binding<String>` computed on the view:

```swift
private var themeBinding: Binding<String> {
    Binding(
        get: { model.themeManager.theme.stableID },
        set: { newID in
            guard let newTheme = AppTheme(stableID: newID) else { return }
            Task { @MainActor in
                model.themeManager.setTheme(newTheme)
            }
        }
    )
}
```

If `setTheme(_:)` doesn't exist on `ThemeManager` yet, add it:

```swift
public func setTheme(_ theme: AppTheme) {
    self.theme = theme
    UserDefaults.standard.set(theme.stableID, forKey: "appearance.theme")
}
```

(Update the existing init to read via `AppTheme(stableID:)` instead of `AppTheme(rawValue:)`.)

### Task B.3: Add the "Themes" section to Settings → Appearance

**Files:** Modify `Sources/AtollApp/Views/AppearanceSettingsPane.swift`.

Below the existing theme picker row, add a new `Section`:

```swift
Section(lang.t("settings.theme.customSection")) {
    if model.themeManager.customThemes.isEmpty {
        Text(lang.t("settings.theme.customEmpty"))
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
    } else {
        ForEach(model.themeManager.customThemes) { custom in
            customThemeRow(custom)
        }
    }
    HStack(spacing: 12) {
        Button(lang.t("settings.theme.createFromPreset")) {
            isPresentingPresetChooser = true
        }
        Button(lang.t("settings.theme.importFromFile")) {
            presentImportPanel()
        }
    }
}
.confirmationDialog(
    lang.t("settings.theme.preset.choose"),
    isPresented: $isPresentingPresetChooser,
    titleVisibility: .visible
) {
    ForEach(AppTheme.builtIn, id: \.stableID) { preset in
        Button(preset.displayName) {
            createCustomFromPreset(preset)
        }
    }
    Button(lang.t("settings.cancel"), role: .cancel) { }
}
.alert(
    lang.t("settings.theme.import.failed"),
    isPresented: $isPresentingImportError,
    presenting: importErrorMessage
) { _ in
    Button(lang.t("settings.ok"), role: .cancel) { }
} message: { msg in
    Text(msg)
}
```

`customThemeRow(_:)` is a helper that renders one row with rename / duplicate / delete / export actions. Add it:

```swift
@ViewBuilder
private func customThemeRow(_ theme: CustomTheme) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 2) {
            Text(theme.displayName)
                .font(.system(size: 13))
            Text(lang.t("settings.theme.customRow.subtitle", theme.basedOn.displayName))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        Spacer()
        Menu {
            Button(lang.t("settings.theme.row.rename")) { renameTarget = theme }
            Button(lang.t("settings.theme.row.duplicate")) { duplicateTheme(theme) }
            Button(lang.t("settings.theme.row.export")) { exportTheme(theme) }
            Divider()
            Button(lang.t("settings.theme.row.delete"), role: .destructive) {
                deleteTarget = theme
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
```

Add the supporting `@State` properties and helper methods:

```swift
@State private var isPresentingPresetChooser = false
@State private var isPresentingImportError = false
@State private var importErrorMessage: String? = nil
@State private var renameTarget: CustomTheme? = nil
@State private var deleteTarget: CustomTheme? = nil

private func createCustomFromPreset(_ preset: AppTheme) {
    let preset_displayName = preset.displayName
    let theme = CustomTheme.fork(from: preset, displayName: "\(preset_displayName) copy")
    Task { @MainActor in
        do {
            try await model.themeManager.customRegistry.save(theme)
            await model.themeManager.refreshCustomThemes()
            model.themeManager.setTheme(.custom(id: theme.id))
        } catch {
            importErrorMessage = error.localizedDescription
            isPresentingImportError = true
        }
    }
}

private func duplicateTheme(_ theme: CustomTheme) {
    Task { @MainActor in
        do {
            _ = try await model.themeManager.customRegistry.duplicate(id: theme.id)
            await model.themeManager.refreshCustomThemes()
        } catch {
            importErrorMessage = error.localizedDescription
            isPresentingImportError = true
        }
    }
}

private func presentImportPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.prompt = NSLocalizedString("settings.theme.import.button", comment: "")
    if panel.runModal() == .OK, let url = panel.url {
        Task { @MainActor in
            do {
                let theme = try await model.themeManager.customRegistry.importTheme(from: url)
                await model.themeManager.refreshCustomThemes()
                model.themeManager.setTheme(.custom(id: theme.id))
            } catch {
                importErrorMessage = error.localizedDescription
                isPresentingImportError = true
            }
        }
    }
}

private func exportTheme(_ theme: CustomTheme) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "\(theme.displayName).json"
    if panel.runModal() == .OK, let url = panel.url {
        Task { @MainActor in
            do {
                try await model.themeManager.customRegistry.exportTheme(theme, to: url)
            } catch {
                importErrorMessage = error.localizedDescription
                isPresentingImportError = true
            }
        }
    }
}

private func performDelete(_ theme: CustomTheme) {
    Task { @MainActor in
        do {
            try await model.themeManager.customRegistry.delete(id: theme.id)
            await model.themeManager.refreshCustomThemes()
            // If the deleted theme was active, fall back to mocha.
            if case .custom(let id) = model.themeManager.theme, id == theme.id {
                model.themeManager.setTheme(.mocha)
            }
        } catch {
            importErrorMessage = error.localizedDescription
            isPresentingImportError = true
        }
    }
}
```

Wire the rename + delete confirmation dialogs:

```swift
.alert(
    lang.t("settings.theme.delete.confirm"),
    isPresented: deleteAlertBinding,
    presenting: deleteTarget
) { theme in
    Button(lang.t("settings.theme.row.delete"), role: .destructive) {
        performDelete(theme)
    }
    Button(lang.t("settings.cancel"), role: .cancel) { }
} message: { theme in
    Text(lang.t("settings.theme.delete.message", theme.displayName))
}
.sheet(item: $renameTarget) { theme in
    RenameThemeSheet(
        original: theme,
        onSave: { newName in
            renameTheme(theme, to: newName)
            renameTarget = nil
        },
        onCancel: { renameTarget = nil }
    )
}

private var deleteAlertBinding: Binding<Bool> {
    Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }
    )
}

private func renameTheme(_ theme: CustomTheme, to newName: String) {
    var updated = theme
    updated.displayName = newName
    Task { @MainActor in
        do {
            try await model.themeManager.customRegistry.save(updated)
            await model.themeManager.refreshCustomThemes()
        } catch {
            importErrorMessage = error.localizedDescription
            isPresentingImportError = true
        }
    }
}
```

Add `RenameThemeSheet` in the same file (kept private):

```swift
private struct RenameThemeSheet: View {
    let original: CustomTheme
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draftName: String

    init(original: CustomTheme, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.onSave = onSave
        self.onCancel = onCancel
        self._draftName = State(initialValue: original.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("settings.theme.rename.title", comment: ""))
                .font(.headline)
            TextField(NSLocalizedString("settings.theme.rename.placeholder", comment: ""), text: $draftName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(NSLocalizedString("settings.cancel", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("settings.save", comment: "")) {
                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(trimmed.isEmpty ? original.displayName : trimmed)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

### Task B.4: Add the localized string keys

**Files:** Modify `Sources/AtollApp/Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`.

**Step B.4.1: Determine where `settings.theme.*` keys live**

```bash
grep -n "settings\\.theme" Sources/AtollApp/Resources/en.lproj/Localizable.strings | head
```

**Step B.4.2: Add the new keys**

For `en.lproj/Localizable.strings`, append:

```
"settings.theme.builtin" = "Built-in";
"settings.theme.custom" = "My themes";
"settings.theme.customSection" = "Custom themes";
"settings.theme.customEmpty" = "No custom themes yet. Create one from a preset or import a JSON file.";
"settings.theme.createFromPreset" = "+ Create from preset…";
"settings.theme.importFromFile" = "Import from file…";
"settings.theme.import.button" = "Import";
"settings.theme.import.failed" = "Couldn't import that theme";
"settings.theme.preset.choose" = "Start from which preset?";
"settings.theme.row.rename" = "Rename…";
"settings.theme.row.duplicate" = "Duplicate";
"settings.theme.row.export" = "Export…";
"settings.theme.row.delete" = "Delete…";
"settings.theme.customRow.subtitle" = "forked from %@";
"settings.theme.delete.confirm" = "Delete this theme?";
"settings.theme.delete.message" = "“%@” will be removed from your Atoll library. The original preset isn't affected.";
"settings.theme.rename.title" = "Rename theme";
"settings.theme.rename.placeholder" = "Theme name";
"settings.cancel" = "Cancel";
"settings.save" = "Save";
"settings.ok" = "OK";
```

(If `settings.cancel` / `settings.save` / `settings.ok` already exist — they likely do — skip those three.)

For `zh-Hans.lproj/Localizable.strings`, append (Simplified Chinese):

```
"settings.theme.builtin" = "内置";
"settings.theme.custom" = "我的主题";
"settings.theme.customSection" = "自定义主题";
"settings.theme.customEmpty" = "暂无自定义主题。从预设创建一个，或从 JSON 文件导入。";
"settings.theme.createFromPreset" = "+ 从预设创建…";
"settings.theme.importFromFile" = "从文件导入…";
"settings.theme.import.button" = "导入";
"settings.theme.import.failed" = "无法导入主题";
"settings.theme.preset.choose" = "从哪个预设开始？";
"settings.theme.row.rename" = "重命名…";
"settings.theme.row.duplicate" = "复制";
"settings.theme.row.export" = "导出…";
"settings.theme.row.delete" = "删除…";
"settings.theme.customRow.subtitle" = "派生自 %@";
"settings.theme.delete.confirm" = "删除此主题？";
"settings.theme.delete.message" = "“%@”将从你的 Atoll 主题库中移除。原始预设不受影响。";
"settings.theme.rename.title" = "重命名主题";
"settings.theme.rename.placeholder" = "主题名称";
```

For `zh-Hant.lproj/Localizable.strings`, append (Traditional Chinese):

```
"settings.theme.builtin" = "內建";
"settings.theme.custom" = "我的主題";
"settings.theme.customSection" = "自訂主題";
"settings.theme.customEmpty" = "尚無自訂主題。從預設建立一個,或從 JSON 檔案匯入。";
"settings.theme.createFromPreset" = "+ 從預設建立…";
"settings.theme.importFromFile" = "從檔案匯入…";
"settings.theme.import.button" = "匯入";
"settings.theme.import.failed" = "無法匯入主題";
"settings.theme.preset.choose" = "從哪個預設開始?";
"settings.theme.row.rename" = "重新命名…";
"settings.theme.row.duplicate" = "複製";
"settings.theme.row.export" = "匯出…";
"settings.theme.row.delete" = "刪除…";
"settings.theme.customRow.subtitle" = "衍生自 %@";
"settings.theme.delete.confirm" = "刪除此主題?";
"settings.theme.delete.message" = "「%@」將從你的 Atoll 主題庫中移除。原始預設不受影響。";
"settings.theme.rename.title" = "重新命名主題";
"settings.theme.rename.placeholder" = "主題名稱";
```

### Task B.5: Build + verify existing tests still pass

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -3
# Expected: build clean, 359/359 tests still passing (Phase B adds no new tests)
```

### Task B.6: Commit Phase B

```bash
git add Sources/AtollApp/Views/AppearanceSettingsPane.swift \
        Sources/AtollApp/ThemeManager.swift \
        Sources/AtollApp/Resources/en.lproj/Localizable.strings \
        Sources/AtollApp/Resources/zh-Hans.lproj/Localizable.strings \
        Sources/AtollApp/Resources/zh-Hant.lproj/Localizable.strings

git commit -m "$(cat <<'EOF'
feat(theme): Phase 2B — Themes section + import/export + grouped picker

Settings → Appearance gains a "Custom themes" section with rename,
duplicate, export, delete actions per row, plus "+ Create from
preset…" and "Import from file…" buttons. The theme picker grows a
"My themes" group below the built-ins. Phase 3 will add the in-app
26-picker editor; Phase 2 ships the duplicate-only flow + JSON
import/export.

- Picker uses Section(builtin) + Section(custom) and tags by
  AppTheme.stableID for clean Codable persistence.
- "+ Create from preset…" → confirmationDialog with the 5 built-ins
  → CustomTheme.fork(from:displayName:) → save → switch picker.
- "Import from file…" → NSOpenPanel(.json) → registry.importTheme →
  fresh UUID assigned → switch picker. Errors surface in alert.
- Per-row Menu (•••) with Rename / Duplicate / Export / Delete.
  Rename opens a sheet with TextField; empty trims to the original
  name. Delete confirms before destroying. Export uses NSSavePanel
  with the theme name as default filename.
- 17 new localized string keys × 3 lproj.
- ThemeManager.setTheme(_:) writes the new stableID to UserDefaults.

359/359 tests still green. No new tests in Phase B (UI behavior is
manually verified in Phase D).
EOF
)"
```

### Task B.7: Hand off to tester

`SendMessage` to `'p2-tester'`:

> Phase B complete at commit `<sha>`.
>
> Files changed: AppearanceSettingsPane.swift (~280 lines added), ThemeManager.swift (setTheme + stableID rename), 3 Localizable.strings (~17 keys × 3).
>
> Localized string keys added: list them.
>
> Build clean, 359/359 tests green. Begin Phase C — registry tests.

Then exit.

---

## Phase C — tester

**Owner:** `p2-tester` agent.
**Goal:** Lock the data-model contract with unit tests. After Phase C the registry is provably correct against malformed input, save/load roundtrips, deletion, duplication, import-with-fresh-UUID, and the AppTheme migration from old String values.

### Task C.1: `CustomThemeCodableRoundtripTests`

**Files:** Modify `Tests/AtollCoreTests/ThemeTests.swift`.

Append to the existing `struct ThemeTests`:

```swift
@Test
func customThemePalettePerFlavorRoundtripsThroughCodable() throws {
    for theme in AppTheme.builtIn {
        guard let palette = theme.builtInPalette else { continue }
        let data = try JSONEncoder().encode(palette)
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: data)
        #expect(decoded == palette, "Palette for \(theme.displayName) lost data through Codable")
    }
}

@Test
func themePaletteJSONHasSchemaVersionAndIsLight() throws {
    let data = try JSONEncoder().encode(ThemePalette.mocha)
    let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    #expect(dict["schemaVersion"] as? Int == 1)
    #expect(dict["isLight"] as? Bool == false)
    #expect(dict["base"] as? String == ThemePalette.mocha.base.toHex())
}

@Test
func themePaletteRejectsHigherSchemaVersion() throws {
    let mocha = try JSONEncoder().encode(ThemePalette.mocha)
    var dict = try JSONSerialization.jsonObject(with: mocha) as! [String: Any]
    dict["schemaVersion"] = 999
    let bumped = try JSONSerialization.data(withJSONObject: dict)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(ThemePalette.self, from: bumped)
    }
}

@Test
func themePaletteRejectsMalformedHex() throws {
    let mocha = try JSONEncoder().encode(ThemePalette.mocha)
    var dict = try JSONSerialization.jsonObject(with: mocha) as! [String: Any]
    dict["base"] = "xyz123"   // not hex
    let bad = try JSONSerialization.data(withJSONObject: dict)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(ThemePalette.self, from: bad)
    }
}

@Test
func appThemeKeyedShapeRoundtrips() throws {
    for theme in AppTheme.builtIn {
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
        #expect(decoded == theme)
    }
    let custom = AppTheme.custom(id: UUID())
    let data = try JSONEncoder().encode(custom)
    let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
    #expect(decoded == custom)
}

@Test
func appThemeAcceptsLegacyStringForBackwardsCompat() throws {
    let legacy = "\"catppuccinMocha\"".data(using: .utf8)!
    let theme = try JSONDecoder().decode(AppTheme.self, from: legacy)
    #expect(theme == .mocha)

    let legacyFrappe = "\"catppuccinFrappe\"".data(using: .utf8)!
    let f = try JSONDecoder().decode(AppTheme.self, from: legacyFrappe)
    #expect(f == .frappe)
}

@Test
func appThemeStableIDRoundtripsForAllForms() {
    for theme in AppTheme.builtIn {
        let id = theme.stableID
        #expect(AppTheme(stableID: id) == theme)
    }
    let custom = AppTheme.custom(id: UUID())
    #expect(AppTheme(stableID: custom.stableID) == custom)
    // Legacy IDs from pre-fork builds.
    #expect(AppTheme(stableID: "catppuccinMocha") == .mocha)
    // Garbage rejected.
    #expect(AppTheme(stableID: "not-a-theme") == nil)
}
```

Run individually:

```bash
swift test --filter "ThemeTests/customThemePalettePerFlavorRoundtripsThroughCodable" 2>&1 | tail -3
swift test --filter "ThemeTests/themePaletteJSONHasSchemaVersionAndIsLight" 2>&1 | tail -3
swift test --filter "ThemeTests/themePaletteRejectsHigherSchemaVersion" 2>&1 | tail -3
swift test --filter "ThemeTests/themePaletteRejectsMalformedHex" 2>&1 | tail -3
swift test --filter "ThemeTests/appThemeKeyedShapeRoundtrips" 2>&1 | tail -3
swift test --filter "ThemeTests/appThemeAcceptsLegacyStringForBackwardsCompat" 2>&1 | tail -3
swift test --filter "ThemeTests/appThemeStableIDRoundtripsForAllForms" 2>&1 | tail -3
# Expected: all PASSED
```

### Task C.2: `CustomThemeRegistryTests`

**Files:** Create `Tests/AtollCoreTests/CustomThemeRegistryTests.swift`.

```swift
import Foundation
import Testing
@testable import AtollCore

struct CustomThemeRegistryTests {
    /// Each test gets its own temp directory so they don't share state.
    private func makeRegistry() -> (CustomThemeRegistry, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-tests-\(UUID().uuidString)", isDirectory: true)
        return (CustomThemeRegistry(directory: tmp), tmp)
    }

    private func sampleTheme(name: String = "Test") -> CustomTheme {
        CustomTheme.fork(from: .mocha, displayName: name)
    }

    @Test
    func saveLoadPreservesAllFields() async throws {
        let (registry, _) = makeRegistry()
        let original = sampleTheme()
        try await registry.save(original)

        let (registry2, _) = (registry, ()) // fresh load via existing instance is fine
        try await registry2.load()
        let loaded = await registry2.themes
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == original.id)
        #expect(loaded.first?.displayName == original.displayName)
        #expect(loaded.first?.palette == original.palette)
    }

    @Test
    func deleteRemovesTheme() async throws {
        let (registry, _) = makeRegistry()
        let theme = sampleTheme()
        try await registry.save(theme)
        try await registry.delete(id: theme.id)
        let after = await registry.themes
        #expect(after.isEmpty)
    }

    @Test
    func duplicateProducesNewUUIDAndCopySuffix() async throws {
        let (registry, _) = makeRegistry()
        let original = sampleTheme(name: "My Night")
        try await registry.save(original)

        let copy = try await registry.duplicate(id: original.id)
        #expect(copy.id != original.id)
        #expect(copy.displayName == "My Night copy")
        #expect(copy.palette == original.palette)

        let copy2 = try await registry.duplicate(id: original.id)
        #expect(copy2.displayName == "My Night copy 2")
    }

    @Test
    func importFromValidJSONAssignsFreshID() async throws {
        let (registry, _) = makeRegistry()
        let original = sampleTheme(name: "Shared")
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try await registry.exportTheme(original, to: exportURL)

        let imported = try await registry.importTheme(from: exportURL)
        #expect(imported.id != original.id, "Import must assign a fresh UUID")
        #expect(imported.displayName == "Shared")
        #expect(imported.palette == original.palette)
    }

    @Test
    func importFromMalformedJSONThrowsAndDoesNotPersist() async throws {
        let (registry, dir) = makeRegistry()
        let bad = dir.deletingLastPathComponent()
            .appendingPathComponent("bad-\(UUID().uuidString).json")
        try Data("{ this is not json".utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
        let after = await registry.themes
        #expect(after.isEmpty, "Failed import must not leave a partial entry")
    }

    @Test
    func importFromMissingFieldThrowsCleanly() async throws {
        let (registry, dir) = makeRegistry()
        let bad = dir.deletingLastPathComponent()
            .appendingPathComponent("missing-\(UUID().uuidString).json")
        // Valid JSON, but the palette is missing the `green` key.
        try Data("""
        {
          "id": "\(UUID().uuidString)",
          "displayName": "Broken",
          "createdAt": "2026-05-07T00:00:00Z",
          "updatedAt": "2026-05-07T00:00:00Z",
          "basedOn": {"kind":"mocha"},
          "palette": {
            "schemaVersion": 1,
            "isLight": false,
            "base": "162232", "mantle": "10182a", "crust": "0a1220",
            "surface0": "263347", "surface1": "37475e", "surface2": "4a5b75",
            "text": "cdd6f4", "subtext1": "bac2de", "subtext0": "a6adc8",
            "overlay2": "9399b2", "overlay1": "7f849c", "overlay0": "6c7086",
            "rosewater": "f5e0dc", "flamingo": "f2cdcd", "pink": "f5c2e7",
            "mauve": "cba6f7", "red": "f38ba8", "maroon": "eba0ac",
            "peach": "fab387", "yellow": "f9e2af",
            "teal": "94e2d5", "sky": "89dceb", "sapphire": "74c7ec",
            "blue": "89b4fa", "lavender": "b4befe"
          }
        }
        """.utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
    }

    @Test
    func corruptFileInDirIsSkippedDuringLoad() async throws {
        let (registry, dir) = makeRegistry()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Drop one valid file…
        let valid = sampleTheme(name: "Valid")
        try await registry.save(valid)
        // …and one corrupt file alongside it.
        let corrupt = dir.appendingPathComponent("corrupt.json")
        try Data("{ not parseable".utf8).write(to: corrupt)

        try await registry.load()
        let themes = await registry.themes
        #expect(themes.count == 1)
        #expect(themes.first?.id == valid.id)
    }
}
```

### Task C.3: Run the full suite

```bash
swift test 2>&1 | tail -3
# Expected: 359 + 7 (Codable + AppTheme) + 7 (registry) = 373 tests pass
```

If any new test fails, surface to dispatcher with the exact failing assertion. Do NOT mutate the implementation to make tests pass — that's reverse-engineering, not testing.

### Task C.4: Commit Phase C

```bash
git add Tests/AtollCoreTests/ThemeTests.swift Tests/AtollCoreTests/CustomThemeRegistryTests.swift

git commit -m "$(cat <<'EOF'
test(theme): Phase 2C — lock CustomThemeRegistry + Codable contracts

14 new tests across two suites:

ThemeTests additions (7):
- customThemePalettePerFlavorRoundtripsThroughCodable
- themePaletteJSONHasSchemaVersionAndIsLight
- themePaletteRejectsHigherSchemaVersion
- themePaletteRejectsMalformedHex
- appThemeKeyedShapeRoundtrips
- appThemeAcceptsLegacyStringForBackwardsCompat
- appThemeStableIDRoundtripsForAllForms

CustomThemeRegistryTests (7):
- saveLoadPreservesAllFields
- deleteRemovesTheme
- duplicateProducesNewUUIDAndCopySuffix
- importFromValidJSONAssignsFreshID
- importFromMalformedJSONThrowsAndDoesNotPersist
- importFromMissingFieldThrowsCleanly
- corruptFileInDirIsSkippedDuringLoad

Each registry test isolates state via a per-test temp directory.
Total suite: 373/373 green.
EOF
)"
```

### Task C.5: Hand off to reviewer

`SendMessage` to `'p2-reviewer'`:

> Phase C complete at commit `<sha>`. Test count: 373 (14 new). Full suite green. Begin Phase D — CPU smoke + manual JSON import + PR.

Then exit.

---

## Phase D — reviewer

**Owner:** `p2-reviewer` agent.
**Goal:** Confirm the live experience works end-to-end (import a real JSON file via the UI, see it appear, switch to it, restart, see it persist), and open the PR.

### Task D.1: Build dev app

```bash
swift build 2>&1 | tail -3
zsh scripts/launch-dev-app.sh --skip-setup 2>&1 | tail -3
sleep 4 && pgrep -fl "Atoll Dev/Contents/MacOS"
# Capture the PID
```

### Task D.2: CPU regression gate

Wait for session-discovery to settle (≤5% CPU within 180s). Same pattern as Phase 1's reviewer:

```bash
PID=<captured>
until [ "$(ps -p $PID -o %cpu= 2>/dev/null | tr -d ' ' | cut -d, -f1)" -lt 5 ] 2>/dev/null; do
  sleep 5
  ps -p $PID -o %cpu,etime 2>/dev/null | tail -1
done
ps -p $PID -o %cpu,rss,etime 2>/dev/null | head -2
```

If sustained > 5% after 180s, surface to dispatcher.

### Task D.3: Hand-write a sample JSON theme to verify import

```bash
cat > /tmp/atoll-sample-theme.json <<'EOF'
{
  "id": "00000000-0000-0000-0000-000000000001",
  "displayName": "Hand-written Test",
  "createdAt": "2026-05-07T00:00:00Z",
  "updatedAt": "2026-05-07T00:00:00Z",
  "basedOn": {"kind":"mocha"},
  "palette": {
    "schemaVersion": 1,
    "isLight": false,
    "base": "1a1a2e", "mantle": "16213e", "crust": "0f3460",
    "surface0": "1a1a40", "surface1": "232342", "surface2": "2c2c4a",
    "text": "e8eaf6", "subtext1": "c5cae9", "subtext0": "9fa8da",
    "overlay2": "7986cb", "overlay1": "5c6bc0", "overlay0": "3f51b5",
    "rosewater": "f5e0dc", "flamingo": "f2cdcd", "pink": "f5c2e7",
    "mauve": "cba6f7", "red": "f38ba8", "maroon": "eba0ac",
    "peach": "fab387", "yellow": "f9e2af", "green": "a6e3a1",
    "teal": "94e2d5", "sky": "89dceb", "sapphire": "74c7ec",
    "blue": "89b4fa", "lavender": "b4befe"
  }
}
EOF
```

### Task D.4: Manual smoke check (asks user)

`SendMessage` to dispatcher:

> Visual smoke check needed. Please:
> 1. Open Settings → Appearance.
> 2. Confirm a "Custom themes" section appears with the empty-state hint and "+ Create from preset…" + "Import from file…" buttons.
> 3. Click "Import from file…" → choose `/tmp/atoll-sample-theme.json` → confirm "Hand-written Test" appears in the list AND the theme picker switches to it.
> 4. Confirm the panel retints to a deeper navy-blue.
> 5. Right-click (or click the ⋯ menu) on the row → Rename → change to "Test Renamed" → confirm the picker label updates.
> 6. Click Duplicate → confirm "Test Renamed copy" appears.
> 7. Click Delete on the original → confirm dialog → confirm it disappears AND the picker switches to Mocha (since we deleted the active theme).
> 8. Click "+ Create from preset…" → pick Latte → confirm "Catppuccin Latte copy" appears AND picker switches to it.
> 9. Quit the app, relaunch via the Atoll Dev.app — confirm the Latte copy is still in the list and still selected.
>
> Reply "ok" if all 9 steps pass, or describe what failed.

Wait for user reply before proceeding to PR.

### Task D.5: Push branch + open PR

```bash
git push -u origin feat/theme-custom-registry

gh pr create --base main --title "feat(theme): Phase 2 — custom theme registry + import/export" --body "$(cat <<'EOF'
## Summary

Phase 2 of the theme-personalization rollout (design:
`docs/plans/2026-05-06-theme-personalization-design.md`,
plan: `docs/plans/2026-05-07-phase-2-custom-theme-registry-plan.md`).

Users can now author themes outside Atoll (any text editor, any color
tool), import them as JSON, and manage them through Settings →
Appearance: rename / duplicate / export / delete. Built-in flavors
remain read-only; custom themes live as one JSON file each under
`~/Library/Application Support/Atoll/themes/`.

- `ThemePalette: Codable` with `schemaVersion: 1` + flat hex dict
- `AppTheme` migrated to enum-with-associated-value (`.custom(id:)`),
  backwards-compat with old String values
- `CustomTheme` value type + `CustomThemeRegistry` actor (load /
  save / delete / duplicate / import / export)
- Settings → Appearance "Themes" section + per-row Menu (Rename /
  Duplicate / Export / Delete) + "+ Create from preset…" + "Import
  from file…" + grouped picker
- 14 new tests (7 codable + 7 registry, total 373/373 green)
- 17 new localized strings × 3 lproj

Phase 3 (in-app 26-picker editor) lands next on `feat/theme-editor`.

## Test plan

- [x] `swift build` clean
- [x] `swift test` — 373/373 green
- [x] CPU settles ≤ 1% post-launch
- [x] Manual: hand-written JSON imports, lists, persists, renames,
  duplicates, deletes, fork-from-preset works
- [ ] Reviewer visual sign-off

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

gh pr view --json url -q .url
```

### Task D.6: Final report to user

`SendMessage` to dispatcher:

> Phase 2 complete. PR: `<url>`.
>
> Commits on `feat/theme-custom-registry`:
> - `<A-sha>` feat(theme): Phase 2A — CustomTheme + registry + AppTheme migration
> - `<B-sha>` feat(theme): Phase 2B — Themes section + import/export + grouped picker
> - `<C-sha>` test(theme): Phase 2C — lock CustomThemeRegistry + Codable contracts
>
> Tests: 373/373 green. Manual smoke passed (per user). Ready for merge.
>
> Phase 3 (in-app editor) starts on `feat/theme-editor` after merge.

Then exit.

---

## Verification gates summary

| Gate    | Owner       | Pass condition                                                         |
| ------- | ----------- | ---------------------------------------------------------------------- |
| **A→B** | architect   | Build clean. 359 tests green. Phase A commit on branch.                |
| **B→C** | coder       | Build clean. 359 tests green (Phase B adds no tests).                  |
| **C→D** | tester      | Build clean. 373 tests green (14 new). Phase C commit on branch.       |
| **D→**  | reviewer    | CPU ≤ 1%. User visual sign-off (9-step checklist). PR open.            |

If any gate fails, the owning agent `SendMessage`s the dispatcher with the failure detail and exits.

---

## Out of scope (Phase 3 / 4 — do NOT do here)

- The in-app 26-picker editor sheet. "+ Create from preset…" only DUPLICATES a preset and selects it; the user has no way to edit individual colors yet (Phase 3 adds that).
- `themeManager.previewPalette` live-preview wiring beyond the stub property (Phase 3 implements it).
- Frosted panel material (Phase 4).
- Renaming source files (cosmetic deferred per the v1.0 README).
