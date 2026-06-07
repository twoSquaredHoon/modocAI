import Foundation

enum WorkflowStepKind: String, Codable {
    case script
    case prompts
    case voiceover
    case videos
    case clip
}

struct WorkflowNode: Codable, Identifiable, Hashable {
    var id: String
    var step: WorkflowStepKind
    var label: String
    var clipId: String?
    var parentId: String?
    var createdAt: String
    var snapshotDir: String
    var status: String
}

struct WorkflowGraphFile: Codable {
    var nodes: [WorkflowNode]
    var activeNodeId: String?
}

enum WorkflowGraphError: LocalizedError {
    case snapshotMissing
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .snapshotMissing: return "Snapshot folder not found for this run."
        case .copyFailed(let msg): return msg
        }
    }
}

struct WorkflowGraphManager {
    let projectFolder: URL

    private var graphURL: URL { projectFolder.appendingPathComponent("workflow_graph.json") }
    private var runsURL: URL { projectFolder.appendingPathComponent("runs") }

    func load() -> WorkflowGraphFile {
        guard let data = try? Data(contentsOf: graphURL),
              let graph = try? JSONDecoder().decode(WorkflowGraphFile.self, from: data) else {
            return WorkflowGraphFile(nodes: [], activeNodeId: nil)
        }
        return graph
    }

    func save(_ graph: WorkflowGraphFile) throws {
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(graph)
        try data.write(to: graphURL)
    }

    func beginRun(
        step: WorkflowStepKind,
        label: String,
        parentId: String?,
        clipId: String? = nil
    ) -> WorkflowNode {
        let stamp = Self.timestamp()
        let slug = step.rawValue + (clipId.map { "-\($0)" } ?? "")
        let nodeId = "run-\(stamp)-\(slug)"
        let relDir = "runs/\(nodeId)"

        return WorkflowNode(
            id: nodeId,
            step: step,
            label: label,
            clipId: clipId,
            parentId: parentId,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            snapshotDir: relDir,
            status: "running"
        )
    }

    func snapshotProjectState(project: VideoProject, intoRelativeDir relDir: String) throws {
        let dest = projectFolder.appendingPathComponent(relDir)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let artifactNames = [
            "script.txt", "clip_decisions.txt", "clip_prompts.txt", "clips.json",
            "voiceover.wav", "speech.txt", "voiceover_meta.json",
        ]
        for name in artifactNames {
            let src = projectFolder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dst = dest.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
        }

        let videosSrc = project.videosURL
        if FileManager.default.fileExists(atPath: videosSrc.path) {
            let videosDst = dest.appendingPathComponent("videos")
            try? FileManager.default.removeItem(at: videosDst)
            try copyDirectory(from: videosSrc, to: videosDst)
        }
    }

    func restoreSnapshot(relativeDir relDir: String, project: VideoProject) throws {
        let src = projectFolder.appendingPathComponent(relDir)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw WorkflowGraphError.snapshotMissing
        }

        let artifactNames = [
            "script.txt", "clip_decisions.txt", "clip_prompts.txt", "clips.json",
            "voiceover.wav", "speech.txt", "voiceover_meta.json",
        ]
        for name in artifactNames {
            let from = src.appendingPathComponent(name)
            let to = projectFolder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: from.path) {
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.copyItem(at: from, to: to)
            }
        }

        let videosFrom = src.appendingPathComponent("videos")
        if FileManager.default.fileExists(atPath: videosFrom.path) {
            try? FileManager.default.removeItem(at: project.videosURL)
            try copyDirectory(from: videosFrom, to: project.videosURL)
        }
    }

    func ensureGraphFromLegacy(project: VideoProject) throws {
        var graph = load()
        guard graph.nodes.isEmpty else { return }

        if project.hasScript || project.hasClipsJSON {
            var node = beginRun(
                step: project.hasClipsJSON ? .prompts : .script,
                label: "Imported project state",
                parentId: nil
            )
            node.status = "completed"
            try snapshotProjectState(project: project, intoRelativeDir: node.snapshotDir)
            graph.nodes.append(node)
            graph.activeNodeId = node.id
            try save(graph)
        }
    }

    private func copyDirectory(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
        for item in items {
            let name = item.lastPathComponent
            try fm.copyItem(at: item, to: dst.appendingPathComponent(name))
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

extension VideoProject {
    var workflowGraphURL: URL { folderURL.appendingPathComponent("workflow_graph.json") }
    var runsURL: URL { folderURL.appendingPathComponent("runs") }

    func loadWorkflowGraph() -> WorkflowGraphFile {
        WorkflowGraphManager(projectFolder: folderURL).load()
    }
}
