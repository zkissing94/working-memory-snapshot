import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("LM Studio") {
                TextField("Base URL", text: $viewModel.baseURLString)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                    .accessibilityLabel("LM Studio Base URL")
                    .accessibilityHint("Enter the local OpenAI-compatible base URL.")

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
                .frame(maxWidth: 420)
                .accessibilityLabel("Synthesizer Model")
                .accessibilityHint("Choose the local model used to generate Working Memory Snapshots.")

                SecureField("API Token, optional", text: $viewModel.apiToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                    .accessibilityLabel("Optional API Token")
                    .accessibilityHint("Enter an optional bearer token for LM Studio.")

                if viewModel.isNonLoopbackWarningVisible {
                    Label(
                        "This server is not running on this Mac. Project evidence may leave this device.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }

                HStack {
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
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Save the LM Studio settings locally.")
                }
                .disabled(viewModel.isBusy)

                if let message = viewModel.connectionState.message {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if viewModel.connectionState == .testing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: viewModel.connectionState.systemImageName)
                            }
                            Text(message)
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
            }
        }
        .formStyle(.grouped)
        .padding(32)
        .navigationTitle("Settings")
        .task {
            await viewModel.loadSettings()
        }
        .alert("Settings Error", isPresented: viewModel.isShowingError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "Settings could not be updated.")
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .saved, .success:
            .green
        case .idle, .testing:
            .secondary
        case .invalidBaseURL,
             .serverUnreachable,
             .unauthorized,
             .noModels,
             .selectedModelUnavailable,
             .invalidResponse,
             .serverError:
            .orange
        }
    }
}
