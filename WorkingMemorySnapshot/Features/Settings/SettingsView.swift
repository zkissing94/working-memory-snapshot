import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("LM Studio") {
                TextField("Base URL", text: $viewModel.baseURLString)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

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

                SecureField("API Token, optional", text: $viewModel.apiToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

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
                    Button("Refresh Models") {
                        Task {
                            await viewModel.refreshModels()
                        }
                    }
                    Button("Save") {
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .disabled(viewModel.isBusy)

                if let message = viewModel.connectionState.message {
                    HStack(spacing: 8) {
                        if viewModel.connectionState == .testing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: viewModel.connectionState.systemImageName)
                        }
                        Text(message)
                    }
                    .foregroundStyle(statusColor)
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
