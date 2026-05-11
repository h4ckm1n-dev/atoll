import AppKit
import CoreGraphics
import Foundation

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case hover
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

// MARK: - Island appearance

enum IslandClosedDisplayStyle: String, CaseIterable, Identifiable {
    case minimal
    case detailed

    var id: String { rawValue }
}

enum IslandPixelShapeStyle: String, CaseIterable, Identifiable {
    case bars
    case steps
    case blocks
    case matrix
    case glitch
    case visor
    case terminal
    case manga
    case blade
    case cyber
    case waveform
    case custom

    var id: String { rawValue }

    static let basicCases: [IslandPixelShapeStyle] = [
        .bars,
        .steps,
        .blocks,
        .custom,
    ]

    var isAdvanced: Bool {
        !Self.basicCases.contains(self)
    }
}
