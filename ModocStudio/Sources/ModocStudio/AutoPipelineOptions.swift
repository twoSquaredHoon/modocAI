import Foundation

/// Steps to run automatically after creating a project (or from Workflow).
struct AutoPipelineOptions: Equatable {
    var runScript: Bool
    var runArticleCheck: Bool
    var runClipPrompts: Bool
    var runVoiceover: Bool
    var runVideos: Bool

    static let scriptOnly = AutoPipelineOptions(
        runScript: true,
        runArticleCheck: false,
        runClipPrompts: false,
        runVoiceover: false,
        runVideos: false
    )

    static func full(includeVideos: Bool = true) -> AutoPipelineOptions {
        AutoPipelineOptions(
            runScript: true,
            runArticleCheck: true,
            runClipPrompts: true,
            runVoiceover: true,
            runVideos: includeVideos
        )
    }

    var runsMoreThanScript: Bool {
        runArticleCheck || runClipPrompts || runVoiceover || runVideos
    }

    var stepLabels: [String] {
        var labels: [String] = []
        if runScript { labels.append("Script") }
        if runArticleCheck { labels.append("Article check") }
        if runClipPrompts { labels.append("Clip prompts") }
        if runVoiceover { labels.append("Voiceover") }
        if runVideos { labels.append("Veo videos") }
        return labels
    }
}

extension AutoPipelineOptions {
    func pendingSteps(for project: VideoProject) -> [PipelineService.PipelineStep] {
        var steps: [PipelineService.PipelineStep] = []
        if runScript, !project.hasScript {
            steps.append(.generateScript)
        }
        if runArticleCheck, !project.hasScriptVerification {
            steps.append(.verifyScript)
        }
        if runClipPrompts, !project.hasClipsJSON {
            steps.append(.generatePrompts)
        }
        if runVoiceover, !project.hasVoiceover {
            steps.append(.generateVoiceover)
        }
        if runVideos {
            let clips = project.loadClips()
            let status = project.videoStatus(for: clips)
            if status.total == 0 || status.done < status.total {
                steps.append(.generateVideos)
            }
        }
        return steps
    }
}

enum AutoPipelineError: LocalizedError {
    case alreadyRunning
    case nothingToRun

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A pipeline step is already running."
        case .nothingToRun:
            return "All selected pipeline steps are already complete."
        }
    }
}
