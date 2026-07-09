import SwiftUI

private struct AppPolishPreviewCatalog: View {
    @State private var remainingSeconds = 12 * 60 + 34
    @State private var completionTrigger = 1
    @FocusState private var isRowFocused: Bool

    var body: some View {
        ScrollView {
            AppWorkspace(maxWidth: AppVisualTokens.Layout.compactWorkspaceWidth) {
                VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.section) {
                    VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.compact) {
                        Text("Working Memory UI")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("Internal preview catalog for adaptive surfaces, status, controls, and motion.")
                            .foregroundStyle(.secondary)
                    }

                    surfaceExamples
                    statusExamples
                    motionExamples
                    controlExamples
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var surfaceExamples: some View {
        VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.control) {
            AppSectionLabel("Surfaces")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                AppSurface {
                    previewSurfaceContent(title: "Standard", detail: "Default reading surface")
                }
                AppSurface(style: .soft) {
                    previewSurfaceContent(title: "Soft", detail: "Supporting context")
                }
                AppSurface(style: .emphasized) {
                    previewSurfaceContent(title: "Emphasized", detail: "Primary resume content")
                }
                AppSurface(style: .status(.warning)) {
                    previewSurfaceContent(title: "Attention", detail: "Recoverable local issue")
                }
            }
        }
    }

    private var statusExamples: some View {
        VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.control) {
            AppSectionLabel("Status tones")
            HStack(spacing: AppVisualTokens.Spacing.control) {
                ForEach(AppStatusTone.allCases, id: \.self) { tone in
                    AppStatusPill(tone.previewName, systemImage: tone.previewImage, tone: tone)
                }
            }
        }
    }

    private var motionExamples: some View {
        AppSurface(style: .emphasized) {
            VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.related) {
                AppSectionLabel("Motion")
                HStack(spacing: AppVisualTokens.Spacing.related) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DurationFormatter.timerString(from: remainingSeconds))
                            .font(.system(.title, design: .monospaced))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text("remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: Double(20 * 60 - remainingSeconds), total: Double(20 * 60))
                        .frame(maxWidth: 220)

                    AppCompletionHalo(trigger: completionTrigger)
                }

                HStack(spacing: AppVisualTokens.Spacing.control) {
                    Button("Advance timer") {
                        remainingSeconds = max(0, remainingSeconds - 1)
                    }
                    Button("Replay completion") {
                        completionTrigger += 1
                    }
                }
            }
        }
    }

    private var controlExamples: some View {
        VStack(alignment: .leading, spacing: AppVisualTokens.Spacing.control) {
            AppSectionLabel("Interactive states")
            HStack(spacing: AppVisualTokens.Spacing.control) {
                previewIconButton("play.fill", label: "Resume", tone: .accent)
                previewIconButton("checkmark", label: "Complete", tone: .success)
                previewIconButton("pause.fill", label: "Pause", tone: .warning)
                previewIconButton("xmark", label: "End", tone: .error)
                previewIconButton("plus", label: "Disabled", tone: .neutral)
                    .disabled(true)
            }

            Button {} label: {
                HStack(spacing: AppVisualTokens.Spacing.control) {
                    Label("Keyboard-focused row", systemImage: "clock.arrow.circlepath")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    AppStatusPill("Selected", tone: .accent)
                }
                .padding(12)
            }
            .buttonStyle(AppClickableRowButtonStyle(isSelected: true))
            .focused($isRowFocused)

            Text("Hover, press, or tab through the controls to review their visual feedback.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { isRowFocused = true }
    }

    private func previewSurfaceContent(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func previewIconButton(_ systemName: String, label: String, tone: AppStatusTone) -> some View {
        Button {} label: {
            Image(systemName: systemName)
        }
        .buttonStyle(AppIconButtonStyle(tone: tone))
        .appTooltip(label)
        .accessibilityLabel(label)
    }
}

private extension AppStatusTone {
    var previewName: String {
        switch self {
        case .neutral:
            "Neutral"
        case .accent:
            "Active"
        case .success:
            "Complete"
        case .warning:
            "Paused"
        case .error:
            "Error"
        }
    }

    var previewImage: String {
        switch self {
        case .neutral:
            "circle"
        case .accent:
            "timer"
        case .success:
            "checkmark"
        case .warning:
            "pause.fill"
        case .error:
            "exclamationmark"
        }
    }
}

#Preview("UI Polish · Light") {
    AppPolishPreviewCatalog()
        .frame(width: 900, height: 700)
}

#Preview("UI Polish · Dark") {
    AppPolishPreviewCatalog()
        .environment(\.colorScheme, .dark)
        .frame(width: 900, height: 700)
}

#Preview("UI Polish · Reduced Motion") {
    AppPolishPreviewCatalog()
        .environment(\.appReduceMotionOverride, true)
        .frame(width: 900, height: 700)
}
