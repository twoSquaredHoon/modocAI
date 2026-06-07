import AppKit
import Foundation

enum ProjectFolderPicker {
    @MainActor
    static func pickFolder(startingAt: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Choose an existing modocAI project folder."
        panel.prompt = "Open Existing Project"
        panel.directoryURL = startingAt ?? ModocConfig.projectsURL
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.standardizedFileURL
    }

    @MainActor
    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not open project"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension ProjectManifest {
    static func inferPhase(in folder: URL) -> ProjectPhase {
        let project = VideoProject(
            id: folder.path,
            folderURL: folder,
            manifest: ProjectManifest(
                id: folder.lastPathComponent,
                title: "",
                blogURL: "",
                createdAt: "",
                phase: .scriptReview,
                lastError: nil
            )
        )
        if !project.hasScript { return .creatingScript }
        if !project.hasClipsJSON { return .scriptReview }
        let status = project.videoStatus(for: project.loadClips())
        if status.total > 0 && status.done >= status.total { return .ready }
        if project.hasVoiceover { return .voiceoverReview }
        if status.done > 0 { return .voiceoverReview }
        return .promptsReview
    }

    static func blogURL(from script: String) -> String {
        for line in script.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("# source:") {
                return t.dropFirst("# source:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
