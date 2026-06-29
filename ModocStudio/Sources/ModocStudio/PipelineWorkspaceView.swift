import SwiftUI

struct PipelineWorkspaceView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let project = store.selectedProject {
                ProjectDetailView(project: project)
            } else {
                PipelineEmptyStateView()
            }
        }
        .withHomeToolbar(title: "Run Pipeline")
    }
}

struct PipelineEmptyStateView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Run Pipeline")
                .font(.title2.bold())
            Text("Create a new video or open a project to run workflow steps yourself.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("New Project…") {
                    store.showNewProjectSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.borderedProminent)

                Button("Open Existing Project") {
                    store.openExistingProject()
                }
                .keyboardShortcut("o", modifiers: .command)
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
