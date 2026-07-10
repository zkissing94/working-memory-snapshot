//
//  ContentView.swift
//  WorkingMemorySnapshot
//
//  Created by Zachary Kissinger on 6/26/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var projectsViewModel: ProjectsViewModel
    @ObservedObject var sessionViewModel: SessionViewModel
    @ObservedObject var projectDetailViewModel: ProjectDetailViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView(
                viewModel: projectsViewModel,
                activity: sidebarActivity,
                currentSessionSummary: currentSessionSummary,
                canStartSessionForProject: { projectID in
                    guard
                        let project = projectsViewModel.projects.first(where: { $0.id == projectID })
                    else {
                        return false
                    }
                    return sessionViewModel.canStartSession && isReadableDirectory(at: project.rootPath)
                },
                canPauseSessionForProject: { projectID in
                    guard let activeSession = sessionViewModel.activeSession else {
                        return false
                    }
                    guard activeSession.projectID == projectID else {
                        return false
                    }
                    return sessionViewModel.activeBlock?.status == .active
                },
                onSelectProject: { projectID in
                    projectDetailViewModel.resetNavigation(for: projectID)
                },
                onStartSession: { project in
                    sessionViewModel.beginStartSession(for: project)
                },
                onPauseSession: { _ in
                    Task {
                        await sessionViewModel.pauseCurrentBlock()
                    }
                }
            )
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detailContent
                .id(detailRootIdentity)
        }
        .task {
            await projectsViewModel.loadProjects()
            let projectIDs = projectsViewModel.projects.map(\.id)
            async let summaries: Void = projectDetailViewModel.preloadSummaries(for: projectIDs)
            async let recovery: Void = sessionViewModel.loadActiveSessionForRecovery()
            async let settings: Void = settingsViewModel.loadSettings()
            _ = await (summaries, recovery, settings)
        }
        .onChange(of: projectsViewModel.projects) { _, projects in
            projectDetailViewModel.retainProjects(Set(projects.map(\.id)))
        }
        .onChange(of: sessionViewModel.activeSession) { oldSession, newSession in
            guard newSession == nil else {
                return
            }

            Task {
                await projectsViewModel.refreshSidebarMetadata()
                if let projectID = oldSession?.projectID {
                    await projectDetailViewModel.refreshProject(projectID)
                }
            }
        }
        .onChange(of: sessionViewModel.generatedSnapshotContext) { _, context in
            guard let context else {
                return
            }

            if projectsViewModel.selectedProject?.id == context.projectID {
                projectDetailViewModel.presentGeneratedSnapshot(
                    context.snapshot,
                    for: context.projectID
                )
            }
            sessionViewModel.clearGeneratedSnapshotContext()
            Task {
                await projectDetailViewModel.refreshProject(context.projectID)
            }
        }
        .onChange(of: sessionViewModel.blockCompletionPrompt) { _, prompt in
            guard let prompt else {
                return
            }

            selectProject(id: prompt.session.projectID)
        }
        .alert("Project Error", isPresented: projectsViewModel.isShowingError) {
            Button("OK", role: .cancel) {
                projectsViewModel.clearError()
            }
        } message: {
            Text(projectsViewModel.errorMessage ?? "The project could not be updated.")
        }
        .alert("Session Error", isPresented: sessionViewModel.isShowingError) {
            Button("OK", role: .cancel) {
                sessionViewModel.clearError()
            }
        } message: {
            Text(sessionViewModel.errorMessage ?? "The session could not be updated.")
        }
        .alert("Snapshot Error", isPresented: projectDetailViewModel.isShowingError) {
            Button("OK", role: .cancel) {
                projectDetailViewModel.clearError()
            }
        } message: {
            Text(projectDetailViewModel.errorMessage ?? "The snapshot could not be loaded.")
        }
        .sheet(isPresented: sessionViewModel.isShowingRecoverySheet) {
            if let recoveryContext = sessionViewModel.recoveryContext {
                SessionRecoverySheet(
                    context: recoveryContext,
                    onResume: {
                        sessionViewModel.resumeRecoveredSession()
                        selectProject(id: recoveryContext.project.id)
                    },
                    onEnd: {
                        sessionViewModel.beginEndingRecoveredSession()
                        selectProject(id: recoveryContext.project.id)
                    },
                    onCancel: {
                        Task {
                            await sessionViewModel.cancelRecoveredSession()
                        }
                    },
                    onRestoreAccess: {
                        Task {
                            if let restoredProject = await projectsViewModel.restoreProjectAccessFromPicker(
                                for: recoveryContext.project
                            ) {
                                sessionViewModel.updateRecoveredProject(restoredProject)
                                await projectDetailViewModel.checkProjectAccess(for: restoredProject)
                                await projectDetailViewModel.refreshProject(restoredProject.id)
                                selectProject(id: restoredProject.id)
                            }
                        }
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: sessionViewModel.isShowingBlockCompletionPrompt) {
            if let prompt = sessionViewModel.blockCompletionPrompt {
                FocusBlockCompletionSheet(
                    prompt: prompt,
                    isWorking: sessionViewModel.isWorking,
                    onReturn: {
                        sessionViewModel.dismissBlockCompletionPrompt()
                    },
                    onComplete: { summary in
                        Task {
                            await sessionViewModel.completePromptedBlock(summary: summary)
                        }
                    }
                )
                .interactiveDismissDisabled(sessionViewModel.isWorking)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch projectsViewModel.selectedItem {
        case .settings:
            SettingsView(viewModel: settingsViewModel)
        default:
            if projectsViewModel.projects.isEmpty {
                EmptyLibraryWorkspaceView {
                    Task {
                        await projectsViewModel.addProjectFromPicker()
                    }
                }
            } else {
                ProjectDetailContainerView(
                    project: projectsViewModel.selectedProject,
                    projectsViewModel: projectsViewModel,
                    sessionViewModel: sessionViewModel,
                    projectDetailViewModel: projectDetailViewModel
                )
            }
        }
    }

    private var detailRootIdentity: String {
        switch projectsViewModel.selectedItem {
        case .settings:
            "settings"
        case .project(let projectID):
            "project-\(projectID.uuidString)"
        case nil:
            projectsViewModel.projects.isEmpty ? "empty-library" : "no-project"
        }
    }

    private var sidebarActivity: ProjectSidebarActivity? {
        ProjectSidebarActivity.current(
            flow: sessionViewModel.flow,
            activeSession: sessionViewModel.activeSession,
            activeBlock: sessionViewModel.activeBlock,
            sessionBlocks: sessionViewModel.sessionBlocks,
            recoveryContext: sessionViewModel.recoveryContext,
            failedSnapshotSession: sessionViewModel.failedSnapshotSession,
            selectedProjectID: projectsViewModel.selectedProject?.id,
            selectedProjectAccessState: projectsViewModel.selectedProject.map {
                projectDetailViewModel.projectAccessState(for: $0.id)
            } ?? .unknown
        )
    }

    private var currentSessionSummary: CurrentSessionSummary? {
        CurrentSessionSummary.current(
            activeSession: sessionViewModel.activeSession,
            activeBlock: sessionViewModel.activeBlock,
            sessionBlocks: sessionViewModel.sessionBlocks
        )
    }

    private func isReadableDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: path)
    }

    private func selectProject(id projectID: Project.ID) {
        projectDetailViewModel.resetNavigation(for: projectID)
        projectsViewModel.selectProject(id: projectID)
    }
}

#Preview {
    let database = Database(url: URL(fileURLWithPath: "/tmp/working-memory-preview.sqlite3"))
    let repository = ProjectRepository(database: database)
    let sessionRepository = SessionRepository(database: database)
    let snapshotRepository = SnapshotRepository(database: database)
    let settingsRepository = SettingsRepository(database: database)
    let migrator = DatabaseMigrator(database: database)

    ContentView(
        projectsViewModel: ProjectsViewModel(
            repository: repository,
            sessionRepository: sessionRepository,
            snapshotRepository: snapshotRepository,
            migrator: migrator
        ),
        sessionViewModel: SessionViewModel(
            sessionRepository: sessionRepository,
            projectRepository: repository,
            pomodoroBlockRepository: PomodoroBlockRepository(database: database),
            workIncrementRepository: WorkIncrementRepository(database: database),
            snapshotGenerator: PreviewSnapshotGenerator(snapshotRepository: snapshotRepository),
            observationCoordinator: PreviewObservationCoordinator()
        ),
        projectDetailViewModel: ProjectDetailViewModel(
            snapshotRepository: snapshotRepository,
            sessionRepository: sessionRepository,
            pomodoroBlockRepository: PomodoroBlockRepository(database: database),
            workIncrementRepository: WorkIncrementRepository(database: database),
            eventRepository: EventRepository(database: database)
        ),
        settingsViewModel: SettingsViewModel(
            repository: settingsRepository,
            tokenStore: PreviewTokenStore()
        )
    )
}

private actor PreviewTokenStore: LMStudioTokenStore {
    func loadToken() async throws -> String? {
        nil
    }

    func saveToken(_ token: String?) async throws {}

    func deleteToken() async throws {}
}

private struct PreviewSnapshotGenerator: SessionSnapshotGenerating {
    let snapshotRepository: SnapshotRepository

    func generateSnapshot(for project: Project, session: WorkSession) async throws -> Snapshot {
        let draft = SnapshotDraft(
            whatChanged: "Preview snapshot generation is not connected.",
            decisions: [],
            openLoops: [],
            nextAction: "Run the app to generate with LM Studio.",
            resumeBrief: "Preview mode uses a local stand-in snapshot.",
            generatorModel: "preview",
            promptVersion: PromptBuilder.promptVersion
        )
        return try await snapshotRepository.saveOrReplaceSnapshot(draft, for: session.id)
    }
}

@MainActor
private final class PreviewObservationCoordinator: SessionObservationCoordinating {
    var onSummaryChange: (@MainActor (ObservationSessionSummary) -> Void)?

    func startObserving(session: WorkSession, project: Project) async {
        onSummaryChange?(
            ObservationSessionSummary(
                changedFileCount: 0,
                droppedFileChangeCount: 0,
                activeApplicationNames: ["Preview"],
                isGitRepository: nil,
                notes: []
            )
        )
    }

    func stopObservingForCompletion(session: WorkSession, brainDump: String) async {}

    func stopObservingForCancellation(session: WorkSession) async {}
}
