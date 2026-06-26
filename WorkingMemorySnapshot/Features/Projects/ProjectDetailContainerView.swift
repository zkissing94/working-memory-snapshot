import SwiftUI

struct ProjectDetailContainerView: View {
    let project: Project?

    var body: some View {
        if let project {
            ProjectDetailView(project: project)
        } else {
            ContentUnavailableView(
                "No Project Selected",
                systemImage: "folder.badge.questionmark",
                description: Text("Select or add a project from the sidebar.")
            )
        }
    }
}

private struct ProjectDetailView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)

                Text(project.rootPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("Created")
                        .foregroundStyle(.secondary)
                    Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                GridRow {
                    Text("Updated")
                        .foregroundStyle(.secondary)
                    Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.body)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
