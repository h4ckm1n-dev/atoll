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
