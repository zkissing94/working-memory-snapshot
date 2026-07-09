import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            AppWorkspace(
                maxWidth: AppVisualTokens.Layout.compactWorkspaceWidth,
                horizontalPadding: AppVisualTokens.Spacing.workspaceWide,
                verticalPadding: AppVisualTokens.Spacing.workspaceWide
            ) {
                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("LM Studio local generation")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                DashboardSurface(style: .emphasized) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("LM Studio")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Base URL", text: $viewModel.baseURLString)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 520)
                                .accessibilityLabel("LM Studio Base URL")
                                .accessibilityHint("Enter the local OpenAI-compatible base URL.")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Synthesizer Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Synthesizer Model", selection: $viewModel.selectedModelID) {
                                Text("None selected").tag("")
                                ForEach(viewModel.models) { model in
                                    Text(model.id).tag(model.id)
                                }
                                if viewModel.selectedModelIsUnavailable {
                                    Text("\(viewModel.selectedModelID) (unavailable)")
                                        .tag(viewModel.selectedModelID)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 520)
                            .accessibilityLabel("Synthesizer Model")
                            .accessibilityHint("Choose the local model used to generate Working Memory Snapshots.")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Token, optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SecureField("API Token, optional", text: $viewModel.apiToken)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 520)
                                .accessibilityLabel("Optional API Token")
                                .accessibilityHint("Enter an optional bearer token for LM Studio.")
                        }

                        if viewModel.isNonLoopbackWarningVisible {
                            Label(
                                "This server is not running on this Mac. Project evidence may leave this device.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                        }

                        HStack(spacing: 12) {
                            Button("Test Connection") {
                                Task {
                                    await viewModel.testConnection()
                                }
                            }
                            .accessibilityHint("Check whether LM Studio is reachable with the current settings.")

                            Button("Refresh Models") {
                                Task {
                                    await viewModel.refreshModels()
                                }
                            }
                            .accessibilityHint("Load the available model list from LM Studio.")

                            Button("Save") {
                                Task {
                                    await viewModel.saveSettings()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .accessibilityHint("Save the LM Studio settings locally.")
                        }
                        .disabled(viewModel.isBusy)
                    }
                }

                if let message = viewModel.connectionState.message {
                    DashboardSurface(style: .status(statusTone)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                if viewModel.connectionState == .testing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: viewModel.connectionState.systemImageName)
                                }
                                Text(message)
                                    .font(.headline)
                            }
                            if let suggestion = viewModel.connectionState.recoverySuggestion {
                                Text(suggestion)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(statusColor)
                        .accessibilityElement(children: .combine)
                    }
                    .transition(AppMotion.stateTransition(reduceMotion: reduceMotion))
                }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Settings")
        .task {
            await viewModel.loadSettings()
        }
        .animation(
            AppMotion.animation(.standard, reduceMotion: reduceMotion),
            value: viewModel.connectionState
        )
        .alert("Settings Error", isPresented: viewModel.isShowingError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "Settings could not be updated.")
        }
    }

    private var statusColor: Color {
        statusTone.tint
    }

    private var statusTone: AppStatusTone {
        switch viewModel.connectionState {
        case .saved, .success:
            .success
        case .idle, .testing:
            .neutral
        case .invalidBaseURL,
             .serverUnreachable,
             .unauthorized,
             .noModels,
             .selectedModelUnavailable,
             .invalidResponse,
             .serverError:
            .warning
        }
    }
}
