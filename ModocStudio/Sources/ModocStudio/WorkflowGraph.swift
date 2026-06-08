import Foundation

enum WorkflowStepKind: String, Codable {
    case script
    case prompts
    case voiceover
    case videos
    case clip
    /// Full workflow milestone — script, prompts, voiceover, and all clips present.
    case complete
    /// Post-complete edit — full snapshot after the first complete version.
    case revision
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
    /// First full-workflow milestone; edits after this are `.revision` nodes.
    var lastCompleteVersionId: String?
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
    let language: ProjectLanguage

    init(projectFolder: URL, language: ProjectLanguage) {
        self.projectFolder = projectFolder
        self.language = language
    }

    private var languageFolder: URL {
        LanguageWorkspace.directory(
            for: VideoProject(
                id: projectFolder.path,
                folderURL: projectFolder,
                manifest: ProjectManifest(
                    id: projectFolder.lastPathComponent,
                    title: "",
                    blogURL: "",
                    createdAt: "",
                    phase: .scriptReview,
                    language: language,
                    lastError: nil
                )
            ),
            language: language
        )
    }

    private var graphURL: URL { languageFolder.appendingPathComponent("workflow_graph.json") }
    private var runsURL: URL { languageFolder.appendingPathComponent("runs") }

    /// Active-language graph also lives at project root while that language is selected.
    private var rootGraphURL: URL { projectFolder.appendingPathComponent("workflow_graph.json") }

    func load() -> WorkflowGraphFile {
        let url = graphURL
        guard let data = try? Data(contentsOf: url),
              let graph = try? JSONDecoder().decode(WorkflowGraphFile.self, from: data) else {
            return WorkflowGraphFile(nodes: [], activeNodeId: nil)
        }
        return graph
    }

    func save(_ graph: WorkflowGraphFile) throws {
        try FileManager.default.createDirectory(at: languageFolder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(graph)
        try data.write(to: graphURL)
        if language == activeLanguageInManifest() {
            try data.write(to: rootGraphURL)
        }
    }

    private func activeLanguageInManifest() -> ProjectLanguage {
        let manifestURL = projectFolder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ProjectManifest.self, from: data) else {
            return .en
        }
        return manifest.language
    }

    func beginRun(
        step: WorkflowStepKind,
        label: String,
        parentId: String?,
        clipId: String? = nil
    ) -> WorkflowNode {
        let stamp = Self.timestamp()
        let slug: String = switch step {
        case .complete: "complete"
        case .revision: "revision-" + (clipId ?? "edit")
        default: step.rawValue + (clipId.map { "-\($0)" } ?? "")
        }
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

    /// Full project snapshot — script, prompts, clips, voiceover, videos, timing stats.
    static let snapshotArtifactNames = [
        "script.txt", "clip_decisions.txt", "clip_prompts.txt", "clips.json",
        "visual_cast.txt",
        "voiceover.wav", "speech.txt", "voiceover_meta.json",
        "pipeline_stats.json",
    ]

    func recordVersionNode(
        project: VideoProject,
        step: WorkflowStepKind,
        label: String,
        parentId: String?,
        graph: inout WorkflowGraphFile,
        clipId: String? = nil
    ) throws -> WorkflowNode {
        var node = beginRun(step: step, label: label, parentId: parentId, clipId: clipId)
        try snapshotProjectState(project: project, intoRelativeDir: node.snapshotDir)
        node.status = "completed"
        graph.nodes.append(node)
        graph.activeNodeId = node.id
        if step == .complete {
            graph.lastCompleteVersionId = node.id
        }
        try save(graph)
        return node
    }

    func maybeRecordCompleteVersion(
        project: VideoProject,
        graph: inout WorkflowGraphFile
    ) throws {
        let lang = project.manifest.language
        guard WorkflowCompletion.isComplete(project, language: lang) else { return }
        guard graph.lastCompleteVersionId == nil else { return }

        let label = "Complete workflow · \(Self.versionLabelDate())"
        _ = try recordVersionNode(
            project: project,
            step: .complete,
            label: label,
            parentId: graph.activeNodeId,
            graph: &graph
        )
    }

    func snapshotProjectState(project: VideoProject, intoRelativeDir relDir: String) throws {
        let dest = languageFolder.appendingPathComponent(relDir)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let sourceRoot = project.manifest.language == language ? project.folderURL : languageFolder

        let artifactNames = Self.snapshotArtifactNames
        for name in artifactNames {
            let src = sourceRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let dst = dest.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
        }

        let videosSrc = sourceRoot.appendingPathComponent("videos", isDirectory: true)
        if FileManager.default.fileExists(atPath: videosSrc.path) {
            let videosDst = dest.appendingPathComponent("videos")
            try? FileManager.default.removeItem(at: videosDst)
            try copyDirectory(from: videosSrc, to: videosDst)
        }

        let statsSrc = projectFolder.appendingPathComponent("pipeline_stats.json")
        if FileManager.default.fileExists(atPath: statsSrc.path) {
            let statsDst = dest.appendingPathComponent("pipeline_stats.json")
            try? FileManager.default.removeItem(at: statsDst)
            try FileManager.default.copyItem(at: statsSrc, to: statsDst)
        }
    }

    func restoreSnapshot(relativeDir relDir: String, project: VideoProject) throws {
        let src = languageFolder.appendingPathComponent(relDir)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw WorkflowGraphError.snapshotMissing
        }

        let destRoot = project.manifest.language == language ? project.folderURL : languageFolder

        let artifactNames = Self.snapshotArtifactNames
        for name in artifactNames {
            let from = src.appendingPathComponent(name)
            let to = destRoot.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: from.path) {
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.copyItem(at: from, to: to)
            }
        }

        let videosFrom = src.appendingPathComponent("videos")
        if FileManager.default.fileExists(atPath: videosFrom.path) {
            let videosTo = destRoot.appendingPathComponent("videos", isDirectory: true)
            try? FileManager.default.removeItem(at: videosTo)
            try copyDirectory(from: videosFrom, to: videosTo)
        }

        let statsFrom = src.appendingPathComponent("pipeline_stats.json")
        if FileManager.default.fileExists(atPath: statsFrom.path) {
            let statsTo = projectFolder.appendingPathComponent("pipeline_stats.json")
            try? FileManager.default.removeItem(at: statsTo)
            try FileManager.default.copyItem(at: statsFrom, to: statsTo)
        }
    }

    func ensureGraphFromLegacy(project: VideoProject) throws {
        var graph = load()
        guard graph.nodes.isEmpty else { return }

        let langDir = languageFolder
        let script = langDir.appendingPathComponent("script.txt")
        let clips = langDir.appendingPathComponent("clips.json")
        let checkRoot = project.manifest.language == language
        let hasScript = FileManager.default.fileExists(atPath: script.path)
            || (checkRoot && project.hasScript)
        let hasClips = FileManager.default.fileExists(atPath: clips.path)
            || (checkRoot && project.hasClipsJSON)

        if hasScript || hasClips {
            var node = beginRun(
                step: hasClips ? .prompts : .script,
                label: "Imported project state",
                parentId: nil
            )
            node.status = "completed"
            try snapshotProjectState(project: project, intoRelativeDir: node.snapshotDir)
            graph.nodes.append(node)
            graph.activeNodeId = node.id
            if WorkflowCompletion.isComplete(project, language: language) {
                try maybeRecordCompleteVersion(project: project, graph: &graph)
            } else {
                try save(graph)
            }
        }
    }

    private static func versionLabelDate() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date())
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
        loadWorkflowGraph(for: manifest.language)
    }
}

enum WorkflowCompletion {
    /// True when script, clip prompts, voiceover, and every clip video exist for a language.
    static func isComplete(_ project: VideoProject, language: ProjectLanguage) -> Bool {
        guard project.hasScript(for: language),
              project.hasClipsJSON(for: language),
              project.hasVoiceover(for: language) else { return false }
        let clips = project.loadClips(for: language)
        guard !clips.isEmpty else { return false }
        let status = project.videoStatus(for: language, clips: clips)
        return status.total > 0 && status.done >= status.total
    }
}
