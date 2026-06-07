import Foundation

import AppKit

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [VideoProject] = []
    @Published var selectedProjectID: String?
    @Published var showNewProjectSheet = false
    @Published var pipeline = PipelineService()

    var selectedProject: VideoProject? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    init() {
        refreshProjects()
    }

    func refreshProjects() {
        try? FileManager.default.createDirectory(at: ModocConfig.projectsURL, withIntermediateDirectories: true)

        var folderPaths = Set<String>()

        if let entries = try? FileManager.default.contentsOfDirectory(
            at: ModocConfig.projectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for folder in entries where folder.hasDirectoryPath {
                folderPaths.insert(folder.standardizedFileURL.path)
            }
        }

        for path in ModocConfig.openedProjectPaths {
            folderPaths.insert(path)
        }

        var loaded: [VideoProject] = []
        for path in folderPaths {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: path),
                  let project = loadProject(from: folder) else { continue }
            loaded.append(project)
        }

        loaded.sort { $0.manifest.createdAt > $1.manifest.createdAt }
        projects = loaded

        if selectedProjectID == nil, let first = loaded.first {
            selectedProjectID = first.id
        } else if let sel = selectedProjectID, !loaded.contains(where: { $0.id == sel }) {
            selectedProjectID = loaded.first?.id
        }
    }

    func openExistingProject() {
        guard let folder = ProjectFolderPicker.pickFolder() else { return }
        openProject(at: folder)
    }

    func openProject(at folder: URL) {
        let folder = folder.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            ProjectFolderPicker.showError("That path is not a folder.")
            return
        }

        let script = folder.appendingPathComponent("script.txt")
        let clips = folder.appendingPathComponent("clips.json")
        let manifest = folder.appendingPathComponent("project.json")

        guard FileManager.default.fileExists(atPath: script.path)
            || FileManager.default.fileExists(atPath: clips.path)
            || FileManager.default.fileExists(atPath: manifest.path) else {
            ProjectFolderPicker.showError(
                "This folder does not look like a modocAI project.\n\n"
                    + "It needs at least script.txt, clips.json, or project.json."
            )
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: manifest.path) {
                try createManifestForLegacyFolder(folder)
            }
        } catch {
            ProjectFolderPicker.showError(error.localizedDescription)
            return
        }

        ModocConfig.registerOpenedProject(folder)
        refreshProjects()
        selectedProjectID = folder.path
    }

    private func createManifestForLegacyFolder(_ folder: URL) throws {
        let scriptPath = folder.appendingPathComponent("script.txt")
        let script = (try? String(contentsOf: scriptPath, encoding: .utf8)) ?? ""
        let manifest = ProjectManifest(
            id: folder.lastPathComponent,
            title: script.isEmpty
                ? folder.lastPathComponent
                : VideoProject.title(from: script),
            blogURL: ProjectManifest.blogURL(from: script),
            createdAt: ISO8601DateFormatter().string(from: Date()),
            phase: ProjectManifest.inferPhase(in: folder),
            lastError: nil
        )
        try saveManifest(manifest, folder: folder)
    }

    func loadProject(from folder: URL) -> VideoProject? {
        let folder = folder.standardizedFileURL
        let manifestURL = folder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder().decode(ProjectManifest.self, from: data) else {
            return nil
        }
        syncPhase(projectFolder: folder, manifest: &manifest)
        return VideoProject(id: folder.path, folderURL: folder, manifest: manifest)
    }

    private func syncPhase(projectFolder: URL, manifest: inout ProjectManifest) {
        let script = projectFolder.appendingPathComponent("script.txt")
        let clips = projectFolder.appendingPathComponent("clips.json")

        if pipeline.isRunning { return }

        if manifest.phase == .creatingScript || manifest.phase == .generatingPrompts
            || manifest.phase == .generatingVoiceover || manifest.phase == .generatingVideos {
            return
        }

        if !FileManager.default.fileExists(atPath: script.path) {
            manifest.phase = .creatingScript
        } else if !FileManager.default.fileExists(atPath: clips.path) {
            manifest.phase = .scriptReview
        } else if !VideoProject(id: projectFolder.path, folderURL: projectFolder, manifest: manifest).hasVoiceover {
            let project = VideoProject(id: projectFolder.path, folderURL: projectFolder, manifest: manifest)
            let clipList = project.loadClips()
            let status = project.videoStatus(for: clipList)
            if status.total > 0 && status.done >= status.total {
                manifest.phase = project.hasVoiceover ? .ready : .promptsReview
            } else if status.done > 0 {
                manifest.phase = .voiceoverReview
            } else {
                manifest.phase = .promptsReview
            }
        } else {
            let project = VideoProject(id: projectFolder.path, folderURL: projectFolder, manifest: manifest)
            let clipList = project.loadClips()
            let status = project.videoStatus(for: clipList)
            if status.total > 0 && status.done >= status.total {
                manifest.phase = .ready
            } else {
                manifest.phase = .voiceoverReview
            }
        }

        if manifest.phase == .ready || manifest.phase == .scriptReview
            || manifest.phase == .promptsReview || manifest.phase == .voiceoverReview {
            try? saveManifest(manifest, folder: projectFolder)
        }
    }

    func createProject(blogURL: String) async throws {
        let slug = VideoProject.slug(from: blogURL)
        let stamp = Self.timestamp()
        let folderName = "\(slug)-\(stamp)"
        let folder = ModocConfig.projectsURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var manifest = ProjectManifest(
            id: folderName,
            title: slug.replacingOccurrences(of: "-", with: " ").capitalized,
            blogURL: blogURL,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            phase: .creatingScript,
            lastError: nil
        )
        try saveManifest(manifest, folder: folder)

        refreshProjects()
        selectedProjectID = folder.path

        do {
            try await pipeline.runProjectStep(
                VideoProject(id: folder.path, folderURL: folder, manifest: manifest),
                step: .generateScript
            )
            let script = (try? String(contentsOf: folder.appendingPathComponent("script.txt"), encoding: .utf8)) ?? ""
            manifest.title = VideoProject.title(from: script)
            manifest.phase = .scriptReview
            manifest.lastError = nil
            try saveManifest(manifest, folder: folder)

            let proj = VideoProject(id: folder.path, folderURL: folder, manifest: manifest)
            try recordGraphRun(project: proj, step: .generateScript, nodeLabel: "Script", success: true)
        } catch {
            manifest.phase = .failed
            manifest.lastError = error.localizedDescription
            try? saveManifest(manifest, folder: folder)
            throw error
        }

        refreshProjects()
    }

    func runWorkflowStep(_ project: VideoProject, step: PipelineService.PipelineStep) async throws {
        var manifest = project.manifest
        manifest.lastError = nil

        let graphManager = WorkflowGraphManager(projectFolder: project.folderURL)
        try? graphManager.ensureGraphFromLegacy(project: project)
        var graph = graphManager.load()

        let meta = graphMeta(for: step)
        let node = graphManager.beginRun(
            step: meta.kind,
            label: meta.label,
            parentId: graph.activeNodeId,
            clipId: meta.clipId
        )
        graph.nodes.append(node)
        graph.activeNodeId = node.id
        try graphManager.save(graph)

        switch step {
        case .generatePrompts:
            manifest.phase = .generatingPrompts
        case .generateVoiceover:
            manifest.phase = .generatingVoiceover
            try? FileManager.default.removeItem(at: project.voiceoverURL)
        case .generateVideos:
            manifest.phase = .generatingVideos
        case .generateScript:
            manifest.phase = .creatingScript
        case .regenerateClip(let clipId):
            manifest.phase = .generatingVideos
            try? FileManager.default.removeItem(at: project.videoURL(for: clipId))
        }

        try saveManifest(manifest, folder: project.folderURL)
        refreshProjects()

        let latest = projects.first { $0.id == project.id } ?? project

        do {
            try await pipeline.runProjectStep(latest, step: step)
            let updated = loadProject(from: project.folderURL) ?? latest
            try graphManager.snapshotProjectState(project: updated, intoRelativeDir: node.snapshotDir)

            if let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) {
                graph.nodes[idx].status = "completed"
            }
            graph.activeNodeId = node.id
            try graphManager.save(graph)

            manifest = updated.manifest
            manifest.lastError = nil

            switch step {
            case .generateScript:
                manifest.phase = .scriptReview
            case .generatePrompts:
                manifest.phase = .promptsReview
            case .generateVoiceover:
                manifest.phase = .voiceoverReview
            case .generateVideos, .regenerateClip:
                let clips = updated.loadClips()
                let status = updated.videoStatus(for: clips)
                manifest.phase = (status.total > 0 && status.done >= status.total) ? .ready : .voiceoverReview
            }

            try saveManifest(manifest, folder: project.folderURL)
        } catch {
            if let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) {
                graph.nodes[idx].status = "failed"
            }
            try? graphManager.save(graph)
            manifest.phase = .failed
            manifest.lastError = error.localizedDescription
            try? saveManifest(manifest, folder: project.folderURL)
            throw error
        }

        refreshProjects()
    }

    func restoreWorkflowNode(project: VideoProject, nodeId: String) throws {
        let graphManager = WorkflowGraphManager(projectFolder: project.folderURL)
        var graph = graphManager.load()
        guard let node = graph.nodes.first(where: { $0.id == nodeId }) else { return }

        try graphManager.restoreSnapshot(relativeDir: node.snapshotDir, project: project)
        graph.activeNodeId = nodeId
        try graphManager.save(graph)
        refreshProjects()
    }

    private func recordGraphRun(
        project: VideoProject,
        step: PipelineService.PipelineStep,
        nodeLabel: String,
        success: Bool
    ) throws {
        let graphManager = WorkflowGraphManager(projectFolder: project.folderURL)
        var graph = graphManager.load()
        let meta = graphMeta(for: step)
        var node = graphManager.beginRun(
            step: meta.kind,
            label: nodeLabel,
            parentId: graph.activeNodeId,
            clipId: meta.clipId
        )
        node.status = success ? "completed" : "failed"
        if success {
            try graphManager.snapshotProjectState(project: project, intoRelativeDir: node.snapshotDir)
        }
        graph.nodes.append(node)
        graph.activeNodeId = node.id
        try graphManager.save(graph)
    }

    private func graphMeta(for step: PipelineService.PipelineStep) -> (
        kind: WorkflowStepKind, label: String, clipId: String?
    ) {
        switch step {
        case .generateScript:
            return (.script, "Script", nil)
        case .generatePrompts:
            return (.prompts, "Clip prompts", nil)
        case .generateVoiceover:
            return (.voiceover, "Voiceover", nil)
        case .generateVideos:
            return (.videos, "All video clips", nil)
        case .regenerateClip(let id):
            return (.clip, "Clip: \(id)", id)
        }
    }

    func proceedToPrompts(project: VideoProject) async throws {
        try await runWorkflowStep(project, step: .generatePrompts)
    }

    func proceedToVoiceover(project: VideoProject) async throws {
        try await runWorkflowStep(project, step: .generateVoiceover)
    }

    func proceedToVideos(project: VideoProject) async throws {
        try await runWorkflowStep(project, step: .generateVideos)
    }

    func saveManifest(_ manifest: ProjectManifest, folder: URL) throws {
        let url = folder.appendingPathComponent("project.json")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url)
    }

    func revealInFinder(_ project: VideoProject) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderURL.path)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }
}

extension ISO8601DateFormatter {
    static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
