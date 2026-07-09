import SwiftUI

private struct AppReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var appReduceMotionOverride: Bool? {
        get { self[AppReduceMotionOverrideKey.self] }
        set { self[AppReduceMotionOverrideKey.self] = newValue }
    }
}

enum AppMotion {
    enum Pace {
        case quick
        case standard
        case emphasis
    }

    static let quickDuration = 0.12
    static let standardDuration = 0.22
    static let emphasisDuration = 0.30
    static let reducedDuration = 0.08

    static func animation(_ pace: Pace, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .linear(duration: reducedDuration)
        }

        switch pace {
        case .quick:
            return .easeOut(duration: quickDuration)
        case .standard:
            return .spring(response: standardDuration, dampingFraction: 0.88)
        case .emphasis:
            return .spring(response: emphasisDuration, dampingFraction: 0.82)
        }
    }

    static func workspaceTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: 0, y: 8))
                .combined(with: .scale(scale: 0.99)),
            removal: .opacity
                .combined(with: .offset(x: 0, y: -4))
                .combined(with: .scale(scale: 0.995))
        )
    }

    static func stateTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        return .opacity
            .combined(with: .offset(x: 0, y: 6))
            .combined(with: .scale(scale: 0.992, anchor: .top))
    }

    static func insertionTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }

        return .opacity.combined(with: .move(edge: .top))
    }
}
