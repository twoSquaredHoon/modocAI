import Foundation

/// Disk-only project scanning (safe to run off the main thread).
enum ProjectDiskLoader {
    static func scan(
        root: URL,
        openedPaths: [String],
        pipelineRunning: Bool
    ) -> [VideoProject] {
        var folderPaths = Set<String>()
        collectProjectFolderPaths(at: root, into: &folderPaths)

        for path in openedPaths {
            folderPaths.insert(path)
        }

        var loaded: [VideoProject] = []
        for path in folderPaths {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: path),
                  let project = loadProject(from: folder, pipelineRunning: pipelineRunning) else {
                continue
            }
            loaded.append(project)
        }

        return loaded.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    private static func collectProjectFolderPaths(
        at root: URL,
        into paths: inout Set<String>,
        depth: Int = 0
    ) {
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

    private static func isProjectFolder(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path)
    }

    static func loadProject(from folder: URL, pipelineRunning: Bool) -> VideoProject? {
        let folder = folder.standardizedFileURL
        let manifestURL = folder.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder().decode(ProjectManifest.self, from: data) else {
            return nil
        }
        syncPhase(projectFolder: folder, manifest: &manifest, pipelineRunning: pipelineRunning)
        let project = VideoProject(id: folder.path, folderURL: folder, manifest: manifest)
        try? LanguageWorkspace.migrateLegacyIfNeeded(project)
        return project
    }

    private static func syncPhase(
        projectFolder: URL,
        manifest: inout ProjectManifest,
        pipelineRunning: Bool
    ) {
        let script = projectFolder.appendingPathComponent("script.txt")
        let clips = projectFolder.appendingPathComponent("clips.json")

        if pipelineRunning { return }

        if manifest.phase == .creatingScript || manifest.phase == .generatingPrompts
            || manifest.phase == .generatingVoiceover || manifest.phase == .generatingVideos {
            return
        }

        if !FileManager.default.fileExists(atPath: script.path) {
            manifest.phase = .creatingScript
        } else if !FileManager.default.fileExists(atPath: clips.path) {
            manifest.phase = .scriptReview
        } else if !hasVoiceover(in: projectFolder) {
            let project = VideoProject(id: projectFolder.path, folderURL: projectFolder, manifest: manifest)
            let clipList = project.loadClips()
            let status = project.videoStatus(for: clipList)
            if status.total > 0 && status.done >= status.total {
                manifest.phase = hasVoiceover(in: projectFolder) ? .ready : .promptsReview
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
            let path = projectFolder.appendingPathComponent("project.json")
            if let data = try? JSONEncoder().encode(manifest) {
                try? data.write(to: path)
            }
        }
    }

    private static func hasVoiceover(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("voiceover.wav").path)
    }
}
