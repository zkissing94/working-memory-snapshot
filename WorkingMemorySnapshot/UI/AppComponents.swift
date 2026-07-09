import SwiftUI

enum AppSurfaceStyle: Equatable {
    case standard
    case soft
    case emphasized
    case status(AppStatusTone)
}

struct AppSurface<Content: View>: View {
    let style: AppSurfaceStyle
    let isInteractive: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovering = false

    init(
        style: AppSurfaceStyle = .standard,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceShape.fill(fill))
            .overlay(surfaceShape.strokeBorder(border, lineWidth: borderWidth))
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .scaleEffect(isInteractive && isHovering && !reduceMotion ? 1.003 : 1)
            .animation(AppMotion.animation(.quick, reduceMotion: reduceMotion), value: isHovering)
            .onHover { hovering in
                guard isInteractive else {
                    return
                }
                isHovering = hovering
            }
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var fill: Color {
        switch style {
        case .standard:
            Color(nsColor: .textBackgroundColor)
        case .soft:
            Color(nsColor: .controlBackgroundColor)
        case .emphasized:
            Color(nsColor: .textBackgroundColor)
        case .status(let tone):
            tone.softFill
        }
    }

    private var border: Color {
        switch style {
        case .standard, .soft:
            Color(nsColor: .separatorColor).opacity(0.42)
        case .emphasized:
            Color.accentColor.opacity(0.24)
        case .status(let tone):
            tone.border
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .emphasized:
            1.25
        case .standard, .soft, .status:
            1
        }
    }

    private var shadowColor: Color {
        switch style {
        case .soft, .status:
            .clear
        case .standard:
            AppVisualTokens.Elevation.standardColor
        case .emphasized:
            AppVisualTokens.Elevation.emphasizedColor
        }
    }

    private var shadowRadius: CGFloat {
        style == .emphasized
            ? AppVisualTokens.Elevation.emphasizedRadius
            : AppVisualTokens.Elevation.standardRadius
    }

    private var shadowY: CGFloat {
        style == .emphasized
            ? AppVisualTokens.Elevation.emphasizedY
            : AppVisualTokens.Elevation.standardY
    }
}

struct DashboardSurface<Content: View>: View {
    let style: AppSurfaceStyle
    let isInteractive: Bool
    let content: Content

    init(
        style: AppSurfaceStyle = .standard,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        AppSurface(style: style, isInteractive: isInteractive) {
            content
        }
    }
}

struct AppStatusPill: View {
    let title: String
    let systemImage: String?
    let tone: AppStatusTone

    init(_ title: String, systemImage: String? = nil, tone: AppStatusTone) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tone.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tone.softFill))
        .overlay(Capsule().strokeBorder(tone.border, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

struct AppSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.35)
    }
}

struct AppWorkspace<Content: View>: View {
    let maxWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let content: Content

    init(
        maxWidth: CGFloat = AppVisualTokens.Layout.standardWorkspaceWidth,
        horizontalPadding: CGFloat = AppVisualTokens.Spacing.workspace,
        verticalPadding: CGFloat = AppVisualTokens.Spacing.workspace,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct AppIconButtonStyle: ButtonStyle {
    let tone: AppStatusTone

    init(tone: AppStatusTone = .neutral) {
        self.tone = tone
    }

    func makeBody(configuration: Configuration) -> some View {
        AppIconButtonBody(configuration: configuration, tone: tone)
    }
}

struct AppClickableRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let baseFill: Color

    init(
        isSelected: Bool,
        baseFill: Color = Color(nsColor: .controlBackgroundColor)
    ) {
        self.isSelected = isSelected
        self.baseFill = baseFill
    }

    func makeBody(configuration: Configuration) -> some View {
        AppClickableRowButtonBody(
            configuration: configuration,
            isSelected: isSelected,
            baseFill: baseFill
        )
    }
}

struct AppCompletionHalo: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotionOverride) private var reduceMotionOverride
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            if trigger > 0 && !reduceMotion {
                Circle()
                    .stroke(AppStatusTone.success.tint.opacity(0.42), lineWidth: 1.5)
                    .scaleEffect(isExpanded ? 1.9 : 0.65)
                    .opacity(isExpanded ? 0 : 0.75)
                    .accessibilityHidden(true)
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppStatusTone.success.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
        }
        .frame(width: 28, height: 28)
        .onAppear(perform: playIfNeeded)
        .onChange(of: trigger) { _, _ in
            playIfNeeded()
        }
    }

    private func playIfNeeded() {
        guard trigger > 0, !reduceMotion else {
            return
        }
        isExpanded = false
        DispatchQueue.main.async {
            withAnimation(AppMotion.animation(.emphasis, reduceMotion: false)) {
                isExpanded = true
            }
        }
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }
}

private struct AppIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tone: AppStatusTone

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .frame(
                minWidth: AppVisualTokens.Layout.minimumIconTarget,
                minHeight: AppVisualTokens.Layout.minimumIconTarget
            )
            .contentShape(RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous))
            .foregroundStyle(isEnabled ? tone.tint : Color.secondary.opacity(0.55))
            .background(
                RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
                    .strokeBorder(iconBorder, lineWidth: isFocused ? 2 : 1)
            }
            .shadow(color: focusShadow, radius: 3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.65)
            .animation(
                AppMotion.animation(.quick, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
            .animation(AppMotion.animation(.quick, reduceMotion: reduceMotion), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var backgroundFill: Color {
        if configuration.isPressed {
            return tone.tint.opacity(0.16)
        }
        if isHovering {
            return tone.softFill
        }
        return .clear
    }

    private var iconBorder: Color {
        if isFocused {
            return Color.accentColor.opacity(0.85)
        }
        return isHovering ? tone.border : .clear
    }

    private var focusShadow: Color {
        isFocused ? Color.accentColor.opacity(0.22) : .clear
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }
}

private struct AppClickableRowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let baseFill: Color

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .contentShape(rowShape)
            .background(rowShape.fill(fill))
            .overlay(rowShape.strokeBorder(border, lineWidth: isFocused ? 2 : 1))
            .shadow(color: focusShadow, radius: 3)
            .scaleEffect(scale)
            .opacity(isEnabled ? 1 : 0.58)
            .animation(AppMotion.animation(.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(AppMotion.animation(.quick, reduceMotion: reduceMotion), value: isHovering)
            .animation(AppMotion.animation(.standard, reduceMotion: reduceMotion), value: isSelected)
            .onHover { isHovering = $0 }
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppVisualTokens.Radius.standard, style: .continuous)
    }

    private var fill: Color {
        if configuration.isPressed {
            return Color.accentColor.opacity(0.14)
        }
        if isSelected {
            return Color.accentColor.opacity(0.10)
        }
        if isHovering {
            return Color.primary.opacity(0.045)
        }
        return baseFill
    }

    private var border: Color {
        if isFocused {
            return Color.accentColor.opacity(0.85)
        }
        if isSelected {
            return Color.accentColor.opacity(0.30)
        }
        return Color(nsColor: .separatorColor).opacity(0.42)
    }

    private var focusShadow: Color {
        isFocused ? Color.accentColor.opacity(0.22) : .clear
    }

    private var scale: CGFloat {
        guard !reduceMotion else {
            return 1
        }
        if configuration.isPressed {
            return 0.995
        }
        return isHovering ? 1.003 : 1
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }
}

private struct AppTooltipModifier: ViewModifier {
    let text: String
    let delay: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotionOverride) private var reduceMotionOverride
    @State private var isShowingTooltip = false
    @State private var scheduledWorkItem: DispatchWorkItem?

    init(_ text: String, delay: TimeInterval = 0.35) {
        self.text = text
        self.delay = delay
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isShowingTooltip {
                    Text(text)
                        .font(.caption2)
                        .lineLimit(2)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.compact, style: .continuous)
                                .fill(Color.black.opacity(0.90))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppVisualTokens.Radius.compact, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        }
                        .padding(.top, 6)
                        .offset(y: 24)
                        .allowsHitTesting(false)
                        .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 2)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(AppMotion.animation(.quick, reduceMotion: reduceMotion), value: isShowingTooltip)
            .onAppear { isShowingTooltip = false }
            .onDisappear {
                scheduledWorkItem?.cancel()
                isShowingTooltip = false
            }
            .onHover { hovering in
                scheduledWorkItem?.cancel()
                if hovering {
                    let workItem = DispatchWorkItem {
                        isShowingTooltip = true
                    }
                    scheduledWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                } else {
                    isShowingTooltip = false
                }
            }
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }
}

extension View {
    func appTooltip(_ text: String, delay: TimeInterval = 0.35) -> some View {
        modifier(AppTooltipModifier(text, delay: delay))
    }
}
