import Foundation

/// Per-language artifact storage under `languages/{en|ko|es}/`.
/// The project root always mirrors the active language for Python pipeline compatibility.
enum LanguageWorkspace {
    static let artifactNames = [
        "script.txt", "clip_decisions.txt", "clip_prompts.txt", "clips.json",
        "visual_cast.txt",
        "voiceover.wav", "speech.txt", "voiceover_meta.json",
        "workflow_graph.json",
    ]

    static let artifactDirectories = ["videos", "runs"]

    static func directory(for project: VideoProject, language: ProjectLanguage) -> URL {
        project.folderURL
            .appendingPathComponent("languages", isDirectory: true)
            .appendingPathComponent(language.rawValue, isDirectory: true)
    }

    static func migrateLegacyIfNeeded(_ project: VideoProject) throws {
        let languagesRoot = project.folderURL.appendingPathComponent("languages", isDirectory: true)
        if FileManager.default.fileExists(atPath: languagesRoot.path) { return }

        let hasRootWork = artifactNames.contains {
            FileManager.default.fileExists(atPath: project.folderURL.appendingPathComponent($0).path)
        } || FileManager.default.fileExists(atPath: project.videosURL.path)

        guard hasRootWork else { return }

        let langDir = directory(for: project, language: project.manifest.language)
        try FileManager.default.createDirectory(at: langDir, withIntermediateDirectories: true)
        try copyArtifacts(from: project.folderURL, to: langDir, includeGraph: true)
    }

    /// Save the project root (active language workspace) into its language folder.
    static func persistActive(_ project: VideoProject, language: ProjectLanguage) throws {
        let dest = directory(for: project, language: language)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try copyArtifacts(from: project.folderURL, to: dest, includeGraph: true)
    }

    /// Load a language into the project root, or clear root if that language has no work yet.
    static func activate(_ project: VideoProject, language: ProjectLanguage) throws {
        let source = directory(for: project, language: language)
        try clearRootArtifacts(project)
        if hasAnyWork(in: source) {
            try copyArtifacts(from: source, to: project.folderURL, includeGraph: true)
        }
    }

    static func hasAnyWork(in languageDir: URL) -> Bool {
        if artifactNames.contains(where: {
            FileManager.default.fileExists(atPath: languageDir.appendingPathComponent($0).path)
        }) {
            return true
        }
        for dirName in artifactDirectories {
            let dir = languageDir.appendingPathComponent(dirName, isDirectory: true)
            if directoryHasContents(dir) { return true }
        }
        return false
    }

    static func hasScript(in languageDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: languageDir.appendingPathComponent("script.txt").path)
    }

    static func hasClipsJSON(in languageDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: languageDir.appendingPathComponent("clips.json").path)
    }

    static func hasVoiceover(in languageDir: URL) -> Bool {
        let url = languageDir.appendingPathComponent("voiceover.wav")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return false }
        return size > 1000
    }

    static func loadClips(from languageDir: URL) -> [ClipRecord] {
        let url = languageDir.appendingPathComponent("clips.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ClipsFile.self, from: data) else {
            return []
        }
        return file.clips.sorted { VideoProject.sortKey(for: $0.id) < VideoProject.sortKey(for: $1.id) }
    }

    static func videoStatus(for languageDir: URL, clips: [ClipRecord]) -> (done: Int, total: Int) {
        let videosDir = languageDir.appendingPathComponent("videos", isDirectory: true)
        let total = clips.count
        let done = clips.filter { clip in
            let path = videosDir.appendingPathComponent("\(clip.id).mp4")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
                  let size = attrs[.size] as? Int else { return false }
            return size > 1000
        }.count
        return (done, total)
    }

    // MARK: - Private

    private static func clearRootArtifacts(_ project: VideoProject) throws {
        for name in artifactNames {
            let url = project.folderURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        for dirName in artifactDirectories {
            let url = project.folderURL.appendingPathComponent(dirName, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func copyArtifacts(from source: URL, to dest: URL, includeGraph: Bool) throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in artifactNames {
            if name == "workflow_graph.json", !includeGraph { continue }
            let from = source.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            let to = dest.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: to)
            try FileManager.default.copyItem(at: from, to: to)
        }
        for dirName in artifactDirectories {
            let from = source.appendingPathComponent(dirName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            let to = dest.appendingPathComponent(dirName, isDirectory: true)
            try? FileManager.default.removeItem(at: to)
            try copyDirectory(from: from, to: to)
        }
    }

    private static func copyDirectory(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
        for item in items {
            try fm.copyItem(at: item, to: dst.appendingPathComponent(item.lastPathComponent))
        }
    }

    private static func directoryHasContents(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return !items.isEmpty
    }
}
