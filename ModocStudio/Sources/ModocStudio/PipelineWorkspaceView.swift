import SwiftUI

struct PipelineWorkspaceView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        Group {
            if let project = store.pipelineFocusedProject {
                PipelineProjectView(project: project)
            } else {
                RunPipelineHubView()
            }
        }
    }
}

private struct PipelineProjectView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    store.clearPipelineFocus()
                } label: {
                    Label("Back to creation", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ProjectDetailView(project: project)
        }
    }
}
