import SwiftUI

// MARK: - Graph tab

struct WorkflowGraphView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    @State private var graph: WorkflowGraphFile = WorkflowGraphFile(nodes: [], activeNodeId: nil)
    @State private var restoreError: String?
    @State private var selectedNodeId: String?

    private let layoutEngine = WorkflowTimelineLayout()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            timelineBody
        }
        .onAppear { reloadGraph() }
        .onChange(of: project.id) { _, _ in reloadGraph() }
        .onChange(of: store.pipeline.isRunning) { _, _ in
            if !store.pipeline.isRunning { reloadGraph() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Version timeline")
                .font(.headline)
            Text("Runs flow left → right. Regenerating a step forks a new branch downward. The highlighted path is your current project state.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                legendDot(color: .accentColor, label: "Active path")
                legendDot(color: .secondary.opacity(0.5), dashed: true, label: "Alternate version")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let restoreError {
                Text(restoreError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private var timelineBody: some View {
        Group {
            if graph.nodes.isEmpty {
                ContentUnavailableView(
                    "No runs yet",
                    systemImage: "timeline.selection",
                    description: Text("Run workflow steps or regenerate a clip to build the timeline.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    WorkflowTimelineCanvas(
                        layout: layoutEngine.layout(graph: graph),
                        selectedNodeId: selectedNodeId,
                        onSelect: { selectedNodeId = $0.id },
                        onRestore: restore
                    )
                    .padding(32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func legendDot(color: Color, dashed: Bool = false, label: String) -> some View {
        HStack(spacing: 6) {
            if dashed {
                RoundedRectangle(cornerRadius: 1)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 20, height: 2)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 20, height: 2)
            }
            Text(label)
        }
    }

    private func reloadGraph() {
        let manager = WorkflowGraphManager(projectFolder: project.folderURL)
        try? manager.ensureGraphFromLegacy(project: project)
        graph = project.loadWorkflowGraph()
        if selectedNodeId == nil {
            selectedNodeId = graph.activeNodeId
        }
    }

    private func restore(_ node: WorkflowNode) {
        restoreError = nil
        do {
            try store.restoreWorkflowNode(project: project, nodeId: node.id)
            reloadGraph()
            selectedNodeId = node.id
        } catch {
            restoreError = error.localizedDescription
        }
    }
}

// MARK: - Layout

struct WorkflowTimelineLayout {
    struct NodePlacement: Identifiable {
        let node: WorkflowNode
        let rect: CGRect
        let isOnActivePath: Bool
        let isActiveTip: Bool

        var id: String { node.id }
    }

    struct Edge {
        let from: CGPoint
        let to: CGPoint
        let isOnActivePath: Bool
    }

    struct Result {
        let nodes: [NodePlacement]
        let edges: [Edge]
        let size: CGSize
    }

    private let nodeSize = CGSize(width: 148, height: 76)
    private let hGap: CGFloat = 44
    private let vGap: CGFloat = 28

    func layout(graph: WorkflowGraphFile) -> Result {
        let activePathIds = Set(activePath(in: graph).map(\.id))
        let activeTipId = graph.activeNodeId
        let roots = graph.nodes.filter { $0.parentId == nil }.sorted { $0.createdAt < $1.createdAt }

        var placements: [NodePlacement] = []
        var edges: [Edge] = []
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for (rootIndex, root) in roots.enumerated() {
            let startY = CGFloat(rootIndex) * (nodeSize.height + vGap * 2)
            layoutSubtree(
                node: root,
                graph: graph,
                x: 0,
                y: startY,
                activePathIds: activePathIds,
                activeTipId: activeTipId,
                placements: &placements,
                edges: &edges,
                maxX: &maxX,
                maxY: &maxY
            )
        }

        let size = CGSize(
            width: max(maxX + 48, 400),
            height: max(maxY + 48, 240)
        )
        return Result(nodes: placements, edges: edges, size: size)
    }

    private func layoutSubtree(
        node: WorkflowNode,
        graph: WorkflowGraphFile,
        x: CGFloat,
        y: CGFloat,
        activePathIds: Set<String>,
        activeTipId: String?,
        placements: inout [NodePlacement],
        edges: inout [Edge],
        maxX: inout CGFloat,
        maxY: inout CGFloat
    ) {
        let rect = CGRect(origin: CGPoint(x: x, y: y), size: nodeSize)
        placements.append(NodePlacement(
            node: node,
            rect: rect,
            isOnActivePath: activePathIds.contains(node.id),
            isActiveTip: node.id == activeTipId
        ))
        maxX = max(maxX, rect.maxX)
        maxY = max(maxY, rect.maxY)

        let children = graph.nodes
            .filter { $0.parentId == node.id }
            .sorted { $0.createdAt < $1.createdAt }

        guard !children.isEmpty else { return }

        let activeChild = children.first { activePathIds.contains($0.id) }
        let alternateChildren = children.filter { !activePathIds.contains($0.id) }

        let nextX = x + nodeSize.width + hGap

        if let activeChild {
            let from = CGPoint(x: rect.maxX, y: rect.midY)
            let to = CGPoint(x: nextX, y: y + nodeSize.height / 2)
            edges.append(Edge(from: from, to: to, isOnActivePath: true))
            layoutSubtree(
                node: activeChild,
                graph: graph,
                x: nextX,
                y: y,
                activePathIds: activePathIds,
                activeTipId: activeTipId,
                placements: &placements,
                edges: &edges,
                maxX: &maxX,
                maxY: &maxY
            )
        }

        for (index, alt) in alternateChildren.enumerated() {
            let branchY = y + nodeSize.height + vGap + CGFloat(index) * (nodeSize.height + vGap)
            let from = CGPoint(x: rect.midX, y: rect.maxY)
            let to = CGPoint(x: nextX, y: branchY + nodeSize.height / 2)
            edges.append(Edge(from: from, to: to, isOnActivePath: false))
            layoutSubtree(
                node: alt,
                graph: graph,
                x: nextX,
                y: branchY,
                activePathIds: activePathIds,
                activeTipId: activeTipId,
                placements: &placements,
                edges: &edges,
                maxX: &maxX,
                maxY: &maxY
            )
        }
    }

    private func activePath(in graph: WorkflowGraphFile) -> [WorkflowNode] {
        guard let tipId = graph.activeNodeId,
              let tip = graph.nodes.first(where: { $0.id == tipId }) else {
            return graph.nodes.filter { $0.parentId == nil }
        }
        var path: [WorkflowNode] = [tip]
        var current = tip
        while let parentId = current.parentId,
              let parent = graph.nodes.first(where: { $0.id == parentId }) {
            path.insert(parent, at: 0)
            current = parent
        }
        return path
    }
}

// MARK: - Canvas

struct WorkflowTimelineCanvas: View {
    let layout: WorkflowTimelineLayout.Result
    let selectedNodeId: String?
    let onSelect: (WorkflowNode) -> Void
    let onRestore: (WorkflowNode) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in layout.edges {
                    var path = Path()
                    path.move(to: edge.from)
                    if edge.isOnActivePath {
                        path.addLine(to: edge.to)
                    } else {
                        let midY = (edge.from.y + edge.to.y) / 2
                        path.addLine(to: CGPoint(x: edge.from.x, y: midY))
                        path.addLine(to: CGPoint(x: edge.to.x, y: midY))
                        path.addLine(to: edge.to)
                    }
                    let style = StrokeStyle(
                        lineWidth: edge.isOnActivePath ? 2.5 : 1.5,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: edge.isOnActivePath ? [] : [6, 4]
                    )
                    context.stroke(
                        path,
                        with: .color(edge.isOnActivePath ? Color.accentColor : Color.secondary.opacity(0.45)),
                        style: style
                    )
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)

            ForEach(layout.nodes) { placement in
                WorkflowTimelineNodeCard(
                    placement: placement,
                    isSelected: selectedNodeId == placement.node.id,
                    onSelect: { onSelect(placement.node) },
                    onRestore: { onRestore(placement.node) }
                )
                .position(x: placement.rect.midX, y: placement.rect.midY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

struct WorkflowTimelineNodeCard: View {
    let placement: WorkflowTimelineLayout.NodePlacement
    let isSelected: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void

    private var node: WorkflowNode { placement.node }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: stepIcon)
                    .font(.caption)
                    .foregroundStyle(placement.isOnActivePath ? Color.accentColor : .secondary)
                Text(node.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                statusPill
                if placement.isActiveTip {
                    Text("current")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            Text(shortDate(node.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            if !placement.isActiveTip && node.status == "completed" {
                Button("Restore") { onRestore() }
                    .controlSize(.mini)
                    .font(.caption2)
            }
        }
        .padding(8)
        .frame(width: 148, height: 76, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: placement.isActiveTip || isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(placement.isOnActivePath ? 0.08 : 0.03), radius: 4, y: 2)
        .onTapGesture { onSelect() }
    }

    private var backgroundFill: Color {
        if placement.isActiveTip {
            return Color.accentColor.opacity(0.12)
        }
        if placement.isOnActivePath {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.7)
    }

    private var borderColor: Color {
        if placement.isActiveTip { return .accentColor }
        if isSelected { return .accentColor.opacity(0.6) }
        if placement.isOnActivePath { return .accentColor.opacity(0.35) }
        return Color.secondary.opacity(0.25)
    }

    private var stepIcon: String {
        switch node.step {
        case .script: "doc.text"
        case .prompts: "list.bullet.rectangle"
        case .voiceover: "waveform"
        case .videos: "film.stack"
        case .clip: "film"
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        let (text, color): (String, Color) = switch node.status {
        case "completed": ("done", .green)
        case "failed": ("failed", .red)
        case "running": ("running", .orange)
        default: (node.status, .secondary)
        }
        Text(text)
            .font(.system(size: 9, weight: .medium))
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
