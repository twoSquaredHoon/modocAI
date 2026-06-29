import Foundation

import AppKit

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [VideoProject] = []
    @Published var selectedProjectID: String?
    @Published var appSection: AppSection = .home
    @Published var browseSelectedDateFolder: String?
    @Published var browseSelectedLanguageFolder: String?
    @Published var showNewProjectSheet = false
    @Published var showSetupSheet = false
    @Published var pipeline = PipelineService()

    var selectedProject: VideoProject? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    init() {
        ModocConfig.bootstrap()
        refreshProjects(autoSelect: false)
        if ModocConfig.needsSetup {
            showSetupSheet = true
        }
    }

    func goHome() {
        appSection = .home
    }

    func enterBrowse() {
        refreshProjects(autoSelect: false)
        if browseSelectedDateFolder == nil {
            browseSelectedDateFolder = batchFolders().first?.id
        }
        syncBrowseLanguageSelection()
        appSection = .browse
    }

    func syncBrowseLanguageSelection() {
        guard let dateID = browseSelectedDateFolder, dateID != ProjectBatchFolder.legacyID else {
            browseSelectedLanguageFolder = nil
            return
        }
        let langs = languageFolders(in: dateID)
        if browseSelectedLanguageFolder == nil
            || !langs.contains(where: { $0.id == browseSelectedLanguageFolder }) {
            browseSelectedLanguageFolder = langs.first?.id
        }
        let inFolder = projects(
            inBatchFolder: dateID,
            languageFolder: browseSelectedLanguageFolder ?? ""
        )
        if !inFolder.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = inFolder.first?.id
        }
    }

    func enterPipeline() {
        refreshProjects(autoSelect: true)
        appSection = .pipeline
    }

    func enterStats() {
        refreshProjects(autoSelect: false)
        appSection = .stats
    }

    func batchFolderName(for project: VideoProject) -> String? {
        let projectsRoot = ModocConfig.projectsURL.standardizedFileURL.path
        let folderPath = project.folderURL.standardizedFileURL.path
        guard folderPath.hasPrefix(projectsRoot + "/") else { return nil }
        let remainder = String(folderPath.dropFirst(projectsRoot.count + 1))
        let parts = remainder.split(separator: "/").map(String.init)
        guard parts.count >= 2, ProjectBatchFolderFormat.isDateBatchFolder(parts[0]) else { return nil }
        return parts[0]
    }

    func languageFolders(in dateFolderID: String) -> [ProjectBatchLanguageFolder] {
        guard dateFolderID != ProjectBatchFolder.legacyID else { return [] }
        let dateURL = ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
        var counts: [String: Int] = [:]
        for folderName in ProjectBatchFolderFormat.languageFolderOrder {
            let langURL = dateURL.appendingPathComponent(folderName, isDirectory: true)
            counts[folderName] = projectFolderPaths(in: langURL).count
        }
        // Legacy: projects sitting directly under the date folder (pre-english/korean layout)
        for path in projectFolderPaths(in: dateURL) {
            guard let project = loadProject(from: URL(fileURLWithPath: path, isDirectory: true)) else {
                continue
            }
            let key = ProjectBatchFolderFormat.folderName(for: project.manifest.language)
            counts[key, default: 0] += 1
        }
        return ProjectBatchFolderFormat.languageFolderOrder.compactMap { folderName in
            let count = counts[folderName, default: 0]
            guard count > 0 else { return nil }
            guard let language = ProjectBatchFolderFormat.language(for: folderName) else { return nil }
            return ProjectBatchLanguageFolder(
                id: folderName,
                displayTitle: ProjectBatchFolderFormat.displayTitle(forLanguageFolder: folderName),
                projectCount: count,
                language: language
            )
        }
    }

    func projects(inBatchFolder dateFolderID: String, languageFolder: String) -> [VideoProject] {
        if dateFolderID == ProjectBatchFolder.legacyID {
            return legacyProjects()
        }
        let dateURL = ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
        var results: [VideoProject] = []
        let langURL = dateURL.appendingPathComponent(languageFolder, isDirectory: true)
        for path in projectFolderPaths(in: langURL) {
            if let project = loadProject(from: URL(fileURLWithPath: path, isDirectory: true)) {
                results.append(project)
            }
        }
        if let language = ProjectBatchFolderFormat.language(for: languageFolder) {
            for path in projectFolderPaths(in: dateURL) {
                guard let project = loadProject(from: URL(fileURLWithPath: path, isDirectory: true)),
                      project.manifest.language == language else { continue }
                results.append(project)
            }
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
            .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    func projects(inBatchFolder folderID: String) -> [VideoProject] {
        if folderID == ProjectBatchFolder.legacyID {
            return legacyProjects()
        }
        return languageFolders(in: folderID).flatMap { projects(inBatchFolder: folderID, languageFolder: $0.id) }
    }

    func batchFolders() -> [ProjectBatchFolder] {
        let root = ModocConfig.projectsURL
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [ProjectBatchFolder] = []
        var legacyCount = 0

        for entry in entries where entry.hasDirectoryPath {
            let name = entry.lastPathComponent
            if ProjectBatchFolderFormat.isDateBatchFolder(name) {
                let count = projects(inBatchFolder: name).count
                let hasActivity = BatchStateReader.hasBatchActivity(
                    in: root.appendingPathComponent(name, isDirectory: true)
                )
                if count > 0 || hasActivity {
                    folders.append(ProjectBatchFolder(
                        id: name,
                        displayTitle: ProjectBatchFolderFormat.displayTitle(for: name),
                        projectCount: max(count, hasActivity ? 1 : 0),
                        sortKey: name
                    ))
                }
                continue
            }
            if isProjectFolder(entry) {
                legacyCount += 1
            }
        }

        if legacyCount > 0 {
            folders.append(ProjectBatchFolder(
                id: ProjectBatchFolder.legacyID,
                displayTitle: "Other projects",
                projectCount: legacyCount,
                sortKey: "0"
            ))
        }

        return folders.sorted { $0.sortKey > $1.sortKey }
    }

    func ensureTodayInBatchFolders(_ folders: [ProjectBatchFolder]) -> [ProjectBatchFolder] {
        let today = BatchRunner.todayFolderID()
        if folders.contains(where: { $0.id == today }) { return folders }
        var result = folders
        result.insert(
            ProjectBatchFolder(
                id: today,
                displayTitle: ProjectBatchFolderFormat.displayTitle(for: today),
                projectCount: projects(inBatchFolder: today).count,
                sortKey: today
            ),
            at: 0
        )
        return result
    }

    private func legacyProjects() -> [VideoProject] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: ModocConfig.projectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.hasDirectoryPath && isProjectFolder($0) }
            .compactMap { loadProject(from: $0) }
            .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    func globalStatsRows() -> [GlobalProjectStatsRow] {
        projects.compactMap { project in
            let summary = PipelineTimeTracker.summaries(for: project)
                .first { $0.language == project.manifest.language }
            guard let summary, summary.totalPipelineSeconds > 0 || summary.stats.startedAt != nil else {
                return nil
            }
            return GlobalProjectStatsRow(
                id: project.id,
                project: project,
                summary: summary,
                batchFolder: batchFolderName(for: project)
            )
        }
        .sorted { $0.summary.totalPipelineSeconds > $1.summary.totalPipelineSeconds }
    }

    private func projectFolderPaths(in directory: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.hasDirectoryPath && isProjectFolder($0) }
            .map { $0.standardizedFileURL.path }
    }

    private func isProjectFolder(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path)
    }

    func chooseModocRoot() {
        guard let root = ProjectFolderPicker.pickModocRoot() else { return }
        ModocConfig.setRootURL(root)
        refreshProjects()
        if ModocConfig.needsSetup {
            showSetupSheet = true
        }
    }

    func openSetupInstructionsInTerminal() {
        let path = ModocConfig.rootURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let source = "cd '\(path)' && ./setup.sh"
        let script = "tell application \"Terminal\" to activate\ntell application \"Terminal\" to do script \"\(source)\""
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    func refreshProjects(autoSelect: Bool = true) {
        do {
            try ModocConfig.ensureProjectsDirectory()
        } catch {
            showSetupSheet = true
            return
        }

        var folderPaths = Set<String>()
        collectProjectFolderPaths(at: ModocConfig.projectsURL, into: &folderPaths)

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

        guard autoSelect else { return }

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
        refreshProjects(autoSelect: true)
        selectedProjectID = folder.path
        appSection = .pipeline
        if let proj = loadProject(from: folder) {
            PipelineTimeTracker.recordProjectOpened(proj)
        }
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
            language: ProjectManifest.inferLanguage(from: script),
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
        let project = VideoProject(id: folder.path, folderURL: folder, manifest: manifest)
        try? LanguageWorkspace.migrateLegacyIfNeeded(project)
        return project
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

    func createProject(
        blogURL: String,
        language: ProjectLanguage = .en,
        autoPipeline: AutoPipelineOptions = .scriptOnly
    ) async throws {
        if ModocConfig.needsSetup {
            showSetupSheet = true
            throw PipelineError.missingSetup
        }

        let slug = VideoProject.slug(from: blogURL)
        let stamp = Self.timestamp()
        let folderName = "\(slug)-\(stamp)"
        let folder = ModocConfig.projectsURL.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            showSetupSheet = true
            throw PipelineError.cannotWriteProjects
        }

        let manifest = ProjectManifest(
            id: folderName,
            title: slug.replacingOccurrences(of: "-", with: " ").capitalized,
            blogURL: blogURL,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            phase: .creatingScript,
            language: language,
            lastError: nil
        )
        try saveManifest(manifest, folder: folder)

        PipelineTimeTracker.recordProjectOpened(
            VideoProject(id: folder.path, folderURL: folder, manifest: manifest)
        )

        refreshProjects()
        selectedProjectID = folder.path
        appSection = .pipeline

        let project = VideoProject(id: folder.path, folderURL: folder, manifest: manifest)
        try await runAutoPipeline(project, options: autoPipeline)

        if let updated = loadProject(from: folder), updated.hasScript {
            var finalManifest = updated.manifest
            finalManifest.title = VideoProject.title(from: updated.loadScript())
            try saveManifest(finalManifest, folder: folder)
        }

        refreshProjects()
    }

    /// Run pipeline steps in workflow order. Skips steps that are already complete.
    func runAutoPipeline(_ project: VideoProject, options: AutoPipelineOptions) async throws {
        guard !pipeline.isRunning else { throw AutoPipelineError.alreadyRunning }

        let steps = options.pendingSteps(for: project)
        guard !steps.isEmpty else { throw AutoPipelineError.nothingToRun }

        for step in steps {
            let current = projects.first { $0.id == project.id }
                ?? loadProject(from: project.folderURL)
                ?? project
            try await runWorkflowStep(current, step: step)
        }
    }

    func runWorkflowStep(_ project: VideoProject, step: PipelineService.PipelineStep) async throws {
        var manifest = project.manifest
        manifest.lastError = nil

        let graphManager = WorkflowGraphManager(
            projectFolder: project.folderURL,
            language: project.manifest.language
        )
        try? graphManager.ensureGraphFromLegacy(project: project)
        var graph = graphManager.load()

        let meta = graphMeta(for: step)
        let revisionMode = graph.lastCompleteVersionId != nil
        let nodeKind = revisionMode ? WorkflowStepKind.revision : meta.kind
        let nodeLabel = revisionMode ? "Change: \(meta.label)" : meta.label

        let node = graphManager.beginRun(
            step: nodeKind,
            label: nodeLabel,
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
        case .regenerateAllClips:
            manifest.phase = .generatingVideos
            for clip in project.loadClips() {
                try? FileManager.default.removeItem(at: project.videoURL(for: clip.id))
            }
        case .createCustomClip(_, let generateVideo):
            if !project.hasClipsJSON {
                manifest.phase = .generatingPrompts
            } else if generateVideo {
                manifest.phase = .generatingVideos
            }
        case .verifyScript:
            break
        case .rewriteScriptLine:
            break
        }

        try saveManifest(manifest, folder: project.folderURL)
        refreshProjects()

        let latest = projects.first { $0.id == project.id } ?? project

        let runId = PipelineTimeTracker.beginAutomatedStep(project: latest, step: step)

        do {
            try await pipeline.runProjectStep(latest, step: step)
            let updated = loadProject(from: project.folderURL) ?? latest
            PipelineTimeTracker.endAutomatedStep(project: updated, runId: runId, success: true)
            try graphManager.snapshotProjectState(project: updated, intoRelativeDir: node.snapshotDir)

            if let idx = graph.nodes.firstIndex(where: { $0.id == node.id }) {
                graph.nodes[idx].status = "completed"
            }
            graph.activeNodeId = node.id
            try graphManager.maybeRecordCompleteVersion(project: updated, graph: &graph)
            try graphManager.save(graph)

            manifest = updated.manifest
            manifest.lastError = nil

            switch step {
            case .generateScript, .verifyScript, .rewriteScriptLine:
                manifest.phase = .scriptReview
                if case .generateScript = step {
                    manifest.title = VideoProject.title(from: updated.loadScript())
                }
            case .generatePrompts:
                manifest.phase = .promptsReview
            case .generateVoiceover:
                manifest.phase = .voiceoverReview
            case .generateVideos, .regenerateClip, .regenerateAllClips, .createCustomClip:
                let clips = updated.loadClips()
                let status = updated.videoStatus(for: clips)
                if updated.hasClipsJSON {
                    manifest.phase = (status.total > 0 && status.done >= status.total) ? .ready : .promptsReview
                } else {
                    manifest.phase = .promptsReview
                }
            }

            try saveManifest(manifest, folder: project.folderURL)
            try? LanguageWorkspace.persistActive(updated, language: updated.manifest.language)
        } catch {
            PipelineTimeTracker.endAutomatedStep(
                project: loadProject(from: project.folderURL) ?? latest,
                runId: runId,
                success: false
            )
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

    func restoreWorkflowNode(
        project: VideoProject,
        nodeId: String,
        language: ProjectLanguage
    ) throws {
        let graphManager = WorkflowGraphManager(
            projectFolder: project.folderURL,
            language: language
        )
        var graph = graphManager.load()
        guard let node = graph.nodes.first(where: { $0.id == nodeId }) else { return }

        try graphManager.restoreSnapshot(relativeDir: node.snapshotDir, project: project)
        graph.activeNodeId = nodeId
        if node.step == .complete {
            graph.lastCompleteVersionId = nodeId
        }
        try graphManager.save(graph)

        if language == project.manifest.language {
            refreshProjects()
        }
    }

    private func recordGraphRun(
        project: VideoProject,
        step: PipelineService.PipelineStep,
        nodeLabel: String,
        success: Bool
    ) throws {
        let graphManager = WorkflowGraphManager(
            projectFolder: project.folderURL,
            language: project.manifest.language
        )
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
        case .regenerateAllClips:
            return (.videos, "Regenerate all clips", nil)
        case .regenerateClip(let id):
            return (.clip, "Clip: \(id)", id)
        case .createCustomClip:
            return (.clip, "Custom clip", nil)
        case .verifyScript:
            return (.script, "Script verification", nil)
        case .rewriteScriptLine(let id):
            return (.script, "Rewrite line \(id)", nil)
        }
    }

    func verifyScript(_ project: VideoProject) async throws {
        try await runWorkflowStep(project, step: .verifyScript)
    }

    func dismissScriptLine(_ project: VideoProject, lineID: String) throws {
        guard !pipeline.isRunning else { throw ScriptEditError.pipelineBusy }
        let latest = projects.first { $0.id == project.id } ?? project
        let script = latest.loadScript()
        guard let updated = ScriptEditor.removeLine(lineID: lineID, from: script) else {
            throw ScriptEditError.lineNotFound(lineID)
        }
        try latest.saveScript(updated)
        try latest.clearScriptVerificationFiles()
        refreshProjects()
    }

    func rewriteScriptLine(_ project: VideoProject, lineID: String) async throws -> ScriptLineEditResult {
        try await runWorkflowStep(project, step: .rewriteScriptLine(lineID))
        let latest = projects.first { $0.id == project.id } ?? project
        try latest.clearScriptVerificationFiles()
        refreshProjects()
        guard let result = latest.loadLastScriptLineEdit() else {
            throw ScriptEditError.lineNotFound(lineID)
        }
        return result
    }

    func disregardVerificationIssue(_ project: VideoProject, lineID: String) throws {
        let latest = projects.first { $0.id == project.id } ?? project
        guard let report = latest.loadScriptVerification() else { return }
        var disregarded = latest.loadVerificationOverrides(for: report)
        disregarded.insert(lineID)
        let overrides = ScriptVerificationOverrides(
            verifiedAt: report.verifiedAt ?? "",
            disregardedLineIDs: disregarded.sorted()
        )
        try latest.saveVerificationOverrides(overrides)
        refreshProjects()
    }

    func restoreVerificationIssue(_ project: VideoProject, lineID: String) throws {
        let latest = projects.first { $0.id == project.id } ?? project
        guard let report = latest.loadScriptVerification() else { return }
        var disregarded = latest.loadVerificationOverrides(for: report)
        disregarded.remove(lineID)
        if disregarded.isEmpty {
            try latest.clearVerificationOverrides()
        } else {
            let overrides = ScriptVerificationOverrides(
                verifiedAt: report.verifiedAt ?? "",
                disregardedLineIDs: disregarded.sorted()
            )
            try latest.saveVerificationOverrides(overrides)
        }
        refreshProjects()
    }

    func createCustomClip(
        _ project: VideoProject,
        lines: [String],
        generateVideo: Bool
    ) async throws -> String {
        let linesFile = project.folderURL.appendingPathComponent(".custom_clip_lines.txt")
        try lines.joined(separator: "\n").write(to: linesFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: linesFile) }

        let beforeIDs = Set(project.loadClips().map(\.id))
        try await runWorkflowStep(
            project,
            step: .createCustomClip(linesFile: linesFile, generateVideo: generateVideo)
        )

        let after = loadProject(from: project.folderURL)?.loadClips() ?? []
        if let created = after.first(where: { $0.id.hasPrefix("custom_") && !beforeIDs.contains($0.id) }) {
            return created.id
        }
        return after.last(where: { $0.id.hasPrefix("custom_") })?.id ?? "custom"
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

    func setProjectLanguage(_ project: VideoProject, language: ProjectLanguage) {
        guard project.manifest.language != language else { return }
        let previous = project.manifest.language
        PipelineTimeTracker.recordLanguageSwitch(project: project, from: previous, to: language)
        do {
            try LanguageWorkspace.persistActive(project, language: previous)
            try LanguageWorkspace.activate(project, language: language)
        } catch {
            // Best-effort file swap when switching languages.
        }
        var manifest = project.manifest
        manifest.language = language
        manifest.lastError = nil
        manifest.phase = ProjectManifest.inferPhase(in: project.folderURL)
        try? saveManifest(manifest, folder: project.folderURL)
        refreshProjects()
    }

    func finalizePipelineLanguage(_ project: VideoProject, language: ProjectLanguage? = nil) {
        let lang = language ?? project.manifest.language
        PipelineTimeTracker.finalizeLanguage(project: project, language: lang)
        let graphManager = WorkflowGraphManager(projectFolder: project.folderURL, language: lang)
        var graph = graphManager.load()
        if WorkflowCompletion.isComplete(project, language: lang) {
            try? graphManager.maybeRecordCompleteVersion(project: project, graph: &graph)
        }
        refreshProjects()
    }

    func isLanguageFinalized(_ project: VideoProject, language: ProjectLanguage) -> Bool {
        PipelineTimeTracker.load(for: project).languages[language.rawValue]?.finalizedAt != nil
    }

    func saveManifest(_ manifest: ProjectManifest, folder: URL) throws {
        let url = folder.appendingPathComponent("project.json")
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url)
    }

    func revealInFinder(_ project: VideoProject) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderURL.path)
    }

    func revealBatchLog(in dateFolderID: String) {
        let folder = ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
        let preferred = folder.appendingPathComponent("daily-batch-run.log")
        if FileManager.default.fileExists(atPath: preferred.path) {
            NSWorkspace.shared.selectFile(preferred.path, inFileViewerRootedAtPath: folder.path)
            return
        }
        if let latest = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter({ $0.lastPathComponent.hasPrefix("batch-") && $0.pathExtension == "log" })
            .sorted(by: { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            })
            .first {
            NSWorkspace.shared.selectFile(latest.path, inFileViewerRootedAtPath: folder.path)
            return
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    func batchState(for dateFolderID: String) -> BatchStateFile? {
        let folder = ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
        return BatchStateReader.load(from: folder)
    }

    func batchInferredProgress(for dateFolderID: String) -> InferredBatchProgress? {
        let folder = ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
        return BatchStateReader.inferProgress(in: folder, projects: projects(inBatchFolder: dateFolderID))
    }

    func batchIsRunning(for dateFolderID: String) -> Bool {
        BatchStateReader.isProcessRunning(for: dateFolderID)
    }

    func startDailyBatch(dateFolderID: String? = nil) {
        let date = dateFolderID ?? BatchRunner.todayFolderID()
        do {
            try BatchRunner.startDailyBatch(dateFolderID: date)
            browseSelectedDateFolder = date
            appSection = .browse
            syncBrowseLanguageSelection()
        } catch {
            ProjectFolderPicker.showError(error.localizedDescription)
        }
    }

    func resumeDailyBatch(dateFolderID: String) {
        do {
            try BatchRunner.resumeDailyBatch(dateFolderID: dateFolderID)
        } catch {
            ProjectFolderPicker.showError(error.localizedDescription)
        }
    }

    func batchNeedsResume(for dateFolderID: String) -> Bool {
        guard dateFolderID != ProjectBatchFolder.legacyID else { return false }
        let folder = ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
        guard BatchStateReader.hasBatchActivity(in: folder) else { return false }

        if batchIsRunning(for: dateFolderID) { return false }

        if let state = batchState(for: dateFolderID) {
            let status = state.effectiveStatus
            if status == .interrupted || status == .failed { return true }
            if status == .running { return true }
            if status == .completed { return false }
        }

        return batchInferredProgress(for: dateFolderID)?.needsResume ?? false
    }

    func resumeBatchInTerminal(dateFolder: String, stopExisting: Bool = false) {
        let root = ModocConfig.rootURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let date = dateFolder.replacingOccurrences(of: "'", with: "'\\''")
        let batchPath = "output/projects/\(date)".replacingOccurrences(of: "'", with: "'\\''")
        var source = "cd '\(root)'"
        if stopExisting {
            source += " && pkill -f 'batch_pipeline.py.*\(batchPath)' 2>/dev/null || true"
            source += " && sleep 1"
        }
        source += " && ./resume-batch.sh '\(date)'"
        let script = "tell application \"Terminal\" to activate\ntell application \"Terminal\" to do script \"\(source)\""
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    func deleteProject(_ project: VideoProject) throws {
        if pipeline.isRunning {
            throw ProjectDeleteError.pipelineRunning
        }

        let folder = project.folderURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: folder.path) else {
            unregisterProjectPath(folder)
            refreshProjects()
            return
        }

        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: folder, resultingItemURL: &trashedURL)
        unregisterProjectPath(folder)

        if selectedProjectID == project.id {
            selectedProjectID = nil
        }
        refreshProjects()
    }

    private func unregisterProjectPath(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        ModocConfig.openedProjectPaths = ModocConfig.openedProjectPaths.filter { $0 != path }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    /// Finds project folders up to three levels deep (date / english|korean / project).
    private func collectProjectFolderPaths(at root: URL, into paths: inout Set<String>, depth: Int = 0) {
        guard depth <= 3 else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries where entry.hasDirectoryPath {
            if isProjectFolder(entry) {
                paths.insert(entry.standardizedFileURL.path)
            } else {
                collectProjectFolderPaths(at: entry, into: &paths, depth: depth + 1)
            }
        }
    }
}

enum ProjectDeleteError: LocalizedError {
    case pipelineRunning

    var errorDescription: String? {
        switch self {
        case .pipelineRunning:
            return "Wait for the current pipeline step to finish before deleting this project."
        }
    }
}

extension ISO8601DateFormatter {
    static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
