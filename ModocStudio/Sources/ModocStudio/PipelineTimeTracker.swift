import Foundation

// MARK: - Models

enum PipelineTimeEventKind: String, Codable {
    case projectStarted = "project_started"
    case languageStarted = "language_started"
    case languageSwitch = "language_switch"
    case automatedStep = "automated_step"
    case manualReview = "manual_review"
    case finalized = "finalized"
}

struct PipelineAutomatedRun: Codable, Identifiable, Hashable {
    var id: String
    var stepKey: String
    var label: String
    var clipId: String?
    var startedAt: String
    var endedAt: String
    var durationSeconds: Double
    var success: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case stepKey = "step_key"
        case label
        case clipId = "clip_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case success
    }
}

struct PipelineManualReview: Codable, Identifiable, Hashable {
    var id: String
    var afterStepKey: String
    var afterStepLabel: String
    var startedAt: String
    var endedAt: String
    var durationSeconds: Double
    var endedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case afterStepKey = "after_step_key"
        case afterStepLabel = "after_step_label"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case endedBy = "ended_by"
    }
}

struct PipelineLanguageSwitch: Codable, Hashable {
    var fromLanguage: String
    var toLanguage: String
    var at: String

    enum CodingKeys: String, CodingKey {
        case fromLanguage = "from_language"
        case toLanguage = "to_language"
        case at
    }
}

struct PipelineLanguageStats: Codable, Hashable {
    var startedAt: String?
    var finalizedAt: String?
    var automatedRuns: [PipelineAutomatedRun]
    var manualReviews: [PipelineManualReview]
    var languageSwitches: [PipelineLanguageSwitch]
    /// Open review period after the last completed step (not yet persisted).
    var openReviewStartedAt: String?
    var openReviewAfterStepKey: String?
    var openReviewAfterStepLabel: String?

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case finalizedAt = "finalized_at"
        case automatedRuns = "automated_runs"
        case manualReviews = "manual_reviews"
        case languageSwitches = "language_switches"
        case openReviewStartedAt = "open_review_started_at"
        case openReviewAfterStepKey = "open_review_after_step_key"
        case openReviewAfterStepLabel = "open_review_after_step_label"
    }

    init(
        startedAt: String? = nil,
        finalizedAt: String? = nil,
        automatedRuns: [PipelineAutomatedRun] = [],
        manualReviews: [PipelineManualReview] = [],
        languageSwitches: [PipelineLanguageSwitch] = [],
        openReviewStartedAt: String? = nil,
        openReviewAfterStepKey: String? = nil,
        openReviewAfterStepLabel: String? = nil
    ) {
        self.startedAt = startedAt
        self.finalizedAt = finalizedAt
        self.automatedRuns = automatedRuns
        self.manualReviews = manualReviews
        self.languageSwitches = languageSwitches
        self.openReviewStartedAt = openReviewStartedAt
        self.openReviewAfterStepKey = openReviewAfterStepKey
        self.openReviewAfterStepLabel = openReviewAfterStepLabel
    }
}

struct PipelineStatsFile: Codable {
    var version: Int
    var projectStartedAt: String?
    var languages: [String: PipelineLanguageStats]

    enum CodingKeys: String, CodingKey {
        case version
        case projectStartedAt = "project_started_at"
        case languages
    }

    static func empty() -> PipelineStatsFile {
        PipelineStatsFile(version: 1, projectStartedAt: nil, languages: [:])
    }
}

// MARK: - Aggregates

struct PipelineLanguageSummary: Identifiable {
    let language: ProjectLanguage
    let stats: PipelineLanguageStats

    var id: String { language.rawValue }

    var totalAutomatedSeconds: Double {
        stats.automatedRuns.reduce(0) { $0 + $1.durationSeconds }
    }

    var totalReviewSeconds: Double {
        let closed = stats.manualReviews.reduce(0) { $0 + $1.durationSeconds }
        return closed + openReviewSeconds
    }

    var openReviewSeconds: Double {
        guard let start = stats.openReviewStartedAt,
              let date = ISO8601DateFormatter().date(from: start) else { return 0 }
        return Date().timeIntervalSince(date)
    }

    var totalPipelineSeconds: Double {
        totalAutomatedSeconds + totalReviewSeconds
    }

    var isFinalized: Bool { stats.finalizedAt != nil }
    var hasOpenReview: Bool { stats.openReviewStartedAt != nil && !isFinalized }
}

enum PipelineDurationFormat {
    static func string(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0s" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %dm %ds", h, m, s) }
        if m > 0 { return String(format: "%dm %ds", m, s) }
        return String(format: "%ds", s)
    }

    static func iso(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter().date(from: iso)
    }
}

// MARK: - Tracker

enum PipelineTimeTracker {
    private static func statsURL(for project: VideoProject) -> URL {
        project.folderURL.appendingPathComponent("pipeline_stats.json")
    }

    static func load(for project: VideoProject) -> PipelineStatsFile {
        let url = statsURL(for: project)
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PipelineStatsFile.self, from: data) else {
            return .empty()
        }
        return file
    }

    static func save(_ file: PipelineStatsFile, project: VideoProject) throws {
        let url = statsURL(for: project)
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: .atomic)
    }

    static func recordProjectOpened(_ project: VideoProject) {
        var file = load(for: project)
        if file.projectStartedAt == nil {
            file.projectStartedAt = PipelineDurationFormat.iso()
            try? save(file, project: project)
        }
    }

    static func recordLanguageSwitch(
        project: VideoProject,
        from previous: ProjectLanguage,
        to next: ProjectLanguage
    ) {
        var file = load(for: project)
        closeOpenReview(in: &file, language: previous, endedBy: "language_switch_to_\(next.rawValue)")
        var prev = langStats(in: &file, language: previous)
        prev.languageSwitches.append(PipelineLanguageSwitch(
            fromLanguage: previous.rawValue,
            toLanguage: next.rawValue,
            at: PipelineDurationFormat.iso()
        ))
        file.languages[previous.rawValue] = prev
        ensureLanguageStarted(in: &file, language: next)
        try? save(file, project: project)
    }

    /// Call immediately before pipeline step runs. Closes open manual review.
    @discardableResult
    static func beginAutomatedStep(
        project: VideoProject,
        step: PipelineService.PipelineStep
    ) -> String {
        let language = project.manifest.language
        let meta = stepMeta(step)
        var file = load(for: project)
        closeOpenReview(in: &file, language: language, endedBy: meta.stepKey)
        if var lang = file.languages[language.rawValue], lang.finalizedAt != nil {
            lang.finalizedAt = nil
            file.languages[language.rawValue] = lang
        }
        ensureLanguageStarted(in: &file, language: language)
        let runId = UUID().uuidString
        let now = PipelineDurationFormat.iso()
        var lang = langStats(in: &file, language: language)
        lang.automatedRuns.append(PipelineAutomatedRun(
            id: runId,
            stepKey: meta.stepKey,
            label: meta.label,
            clipId: meta.clipId,
            startedAt: now,
            endedAt: now,
            durationSeconds: 0,
            success: false
        ))
        file.languages[language.rawValue] = lang
        try? save(file, project: project)
        return runId
    }

    /// Call when pipeline step completes.
    static func endAutomatedStep(
        project: VideoProject,
        runId: String,
        success: Bool
    ) {
        let language = project.manifest.language
        var file = load(for: project)
        guard var lang = file.languages[language.rawValue],
              let idx = lang.automatedRuns.firstIndex(where: { $0.id == runId }) else { return }

        let now = Date()
        let nowISO = PipelineDurationFormat.iso(now)
        var run = lang.automatedRuns[idx]
        run.endedAt = nowISO
        run.success = success
        if let start = PipelineDurationFormat.parse(run.startedAt) {
            run.durationSeconds = max(0, now.timeIntervalSince(start))
        }
        lang.automatedRuns[idx] = run

        if success {
            lang.openReviewStartedAt = nowISO
            lang.openReviewAfterStepKey = run.stepKey
            lang.openReviewAfterStepLabel = run.label
        } else {
            lang.openReviewStartedAt = nil
            lang.openReviewAfterStepKey = nil
            lang.openReviewAfterStepLabel = nil
        }
        file.languages[language.rawValue] = lang
        try? save(file, project: project)
    }

    static func finalizeLanguage(project: VideoProject, language: ProjectLanguage) {
        var file = load(for: project)
        closeOpenReview(in: &file, language: language, endedBy: "finalize")
        var lang = langStats(in: &file, language: language)
        lang.finalizedAt = PipelineDurationFormat.iso()
        lang.openReviewStartedAt = nil
        lang.openReviewAfterStepKey = nil
        lang.openReviewAfterStepLabel = nil
        file.languages[language.rawValue] = lang
        try? save(file, project: project)
    }

    static func summaries(for project: VideoProject) -> [PipelineLanguageSummary] {
        let file = load(for: project)
        return ProjectLanguage.allCases.map { lang in
            PipelineLanguageSummary(
                language: lang,
                stats: file.languages[lang.rawValue] ?? PipelineLanguageStats()
            )
        }
    }

    // MARK: - Private

    private static func langStats(
        in file: inout PipelineStatsFile,
        language: ProjectLanguage
    ) -> PipelineLanguageStats {
        if let existing = file.languages[language.rawValue] { return existing }
        let fresh = PipelineLanguageStats()
        file.languages[language.rawValue] = fresh
        return fresh
    }

    private static func ensureLanguageStarted(
        in file: inout PipelineStatsFile,
        language: ProjectLanguage
    ) {
        var lang = langStats(in: &file, language: language)
        if lang.startedAt == nil {
            lang.startedAt = PipelineDurationFormat.iso()
        }
        file.languages[language.rawValue] = lang
    }

    private static func closeOpenReview(
        in file: inout PipelineStatsFile,
        language: ProjectLanguage,
        endedBy: String
    ) {
        guard var lang = file.languages[language.rawValue],
              let startISO = lang.openReviewStartedAt,
              let afterKey = lang.openReviewAfterStepKey,
              let afterLabel = lang.openReviewAfterStepLabel,
              let start = PipelineDurationFormat.parse(startISO) else { return }

        let now = Date()
        lang.manualReviews.append(PipelineManualReview(
            id: UUID().uuidString,
            afterStepKey: afterKey,
            afterStepLabel: afterLabel,
            startedAt: startISO,
            endedAt: PipelineDurationFormat.iso(now),
            durationSeconds: max(0, now.timeIntervalSince(start)),
            endedBy: endedBy
        ))
        lang.openReviewStartedAt = nil
        lang.openReviewAfterStepKey = nil
        lang.openReviewAfterStepLabel = nil
        file.languages[language.rawValue] = lang
    }

    private static func stepMeta(_ step: PipelineService.PipelineStep) -> (
        stepKey: String, label: String, clipId: String?
    ) {
        switch step {
        case .generateScript:
            return ("generateScript", "Script", nil)
        case .generatePrompts:
            return ("generatePrompts", "Clip prompts", nil)
        case .generateVoiceover:
            return ("generateVoiceover", "Voiceover", nil)
        case .generateVideos:
            return ("generateVideos", "Video clips", nil)
        case .regenerateAllClips:
            return ("regenerateAllClips", "Regenerate all clips", nil)
        case .regenerateClip(let id):
            return ("regenerateClip", "Regenerate clip: \(id)", id)
        }
    }
}
