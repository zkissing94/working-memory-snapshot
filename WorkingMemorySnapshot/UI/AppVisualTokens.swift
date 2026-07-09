import SwiftUI

enum AppVisualTokens {
    enum Radius {
        static let compact: CGFloat = 6
        static let standard: CGFloat = 8
        static let large: CGFloat = 12
    }

    enum Spacing {
        static let compact: CGFloat = 6
        static let control: CGFloat = 8
        static let related: CGFloat = 12
        static let section: CGFloat = 18
        static let workspace: CGFloat = 28
        static let workspaceWide: CGFloat = 32
    }

    enum Layout {
        static let compactWorkspaceWidth: CGFloat = 760
        static let standardWorkspaceWidth: CGFloat = 900
        static let wideWorkspaceWidth: CGFloat = 980
        static let minimumIconTarget: CGFloat = 30
    }

    enum Elevation {
        static let standardColor = Color.black.opacity(0.04)
        static let emphasizedColor = Color.black.opacity(0.07)
        static let standardRadius: CGFloat = 8
        static let emphasizedRadius: CGFloat = 14
        static let standardY: CGFloat = 2
        static let emphasizedY: CGFloat = 5
    }
}

enum AppStatusTone: CaseIterable, Hashable {
    case neutral
    case accent
    case success
    case warning
    case error

    var tint: Color {
        switch self {
        case .neutral:
            Color(nsColor: .secondaryLabelColor)
        case .accent:
            Color.accentColor
        case .success:
            Color(nsColor: .systemGreen)
        case .warning:
            Color(nsColor: .systemOrange)
        case .error:
            Color(nsColor: .systemRed)
        }
    }

    var softFill: Color {
        tint.opacity(self == .neutral ? 0.08 : 0.11)
    }

    var border: Color {
        tint.opacity(self == .neutral ? 0.16 : 0.25)
    }
}
