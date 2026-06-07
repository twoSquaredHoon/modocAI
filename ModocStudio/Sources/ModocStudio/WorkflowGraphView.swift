import SwiftUI

struct WorkflowGraphView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    @State private var graph: WorkflowGraphFile = WorkflowGraphFile(nodes: [], activeNodeId: nil)
    @State private var restoreError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Each run saves a snapshot under runs/. Regenerating creates a new branch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if graph.nodes.isEmpty {
                    ContentUnavailableView(
                        "No runs yet",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Run a workflow step to start the graph.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(rootNodes) { node in
                        WorkflowNodeTree(
                            node: node,
                            graph: graph,
                            depth: 0,
                            onRestore: restore
                        )
                    }
                }

                if let restoreError {
                    Text(restoreError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { reloadGraph() }
        .onChange(of: project.id) { _, _ in reloadGraph() }
        .onChange(of: store.pipeline.isRunning) { _, _ in
            if !store.pipeline.isRunning { reloadGraph() }
        }
    }

    private var rootNodes: [WorkflowNode] {
        graph.nodes.filter { $0.parentId == nil }
    }

    private func reloadGraph() {
        let manager = WorkflowGraphManager(projectFolder: project.folderURL)
        try? manager.ensureGraphFromLegacy(project: project)
        graph = project.loadWorkflowGraph()
    }

    private func restore(_ node: WorkflowNode) {
        restoreError = nil
        do {
            try store.restoreWorkflowNode(project: project, nodeId: node.id)
            reloadGraph()
        } catch {
            restoreError = error.localizedDescription
        }
    }
}

struct WorkflowNodeTree: View {
    let node: WorkflowNode
    let graph: WorkflowGraphFile
    let depth: Int
    let onRestore: (WorkflowNode) -> Void

    private var children: [WorkflowNode] {
        graph.nodes.filter { $0.parentId == node.id }
    }

    private var isActive: Bool {
        graph.activeNodeId == node.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if depth > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2, height: 28)
                }

                stepIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(node.label)
                            .font(.subheadline.weight(.semibold))
                        if isActive {
                            Text("ACTIVE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2), in: Capsule())
                                .foregroundStyle(.green)
                        }
                        statusBadge
                    }
                    Text(shortDate(node.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !isActive && node.status == "completed" {
                    Button("Restore") {
                        onRestore(node)
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .padding(.leading, CGFloat(depth) * 24)

            ForEach(children) { child in
                WorkflowNodeTree(
                    node: child,
                    graph: graph,
                    depth: depth + 1,
                    onRestore: onRestore
                )
            }
        }
    }

    @ViewBuilder
    private var stepIcon: some View {
        let name: String = switch node.step {
        case .script: "doc.text"
        case .prompts: "list.bullet.rectangle"
        case .voiceover: "waveform"
        case .videos: "film.stack"
        case .clip: "film"
        }
        Image(systemName: name)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 28)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (text, color): (String, Color) = switch node.status {
        case "completed": ("done", .green)
        case "failed": ("failed", .red)
        case "running": ("running", .orange)
        default: (node.status, .secondary)
        }
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
    }

    private func shortDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .short
        out.timeStyle = .short
        return out.string(from: date)
    }
}
