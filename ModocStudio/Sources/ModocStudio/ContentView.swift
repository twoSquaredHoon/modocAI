import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let project = store.selectedProject {
                ProjectDetailView(project: project)
            } else {
                EmptyStateView()
            }
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Modoc Studio")
                .font(.title2.bold())
            Text("Create a new video or open a project you already started.")
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
