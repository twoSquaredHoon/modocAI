import Foundation

enum CustomBatchFetchMode: String, CaseIterable, Identifiable {
    case newest = "Newest posts"
    case recent = "Recent window"

    var id: String { rawValue }
}

struct CustomBatchOptions: Equatable {
    var fetchMode: CustomBatchFetchMode = .newest
    var articleCount: Int = 5
    var sinceHours: Int = 24
    var includeEnglish: Bool = true
    var includeKorean: Bool = false
    var includeProcessed: Bool = false
    var processingLimit: Int = 0
    var runArticleCheck: Bool = true
    var runVoiceover: Bool = false
    var runVideos: Bool = false
    var dateFolderID: String = BatchRunner.customFolderID()

    var hasLanguageSelection: Bool {
        includeEnglish || includeKorean
    }

    var resolvedProcessingLimit: Int {
        processingLimit > 0 ? processingLimit : 0
    }

    var selectedLanguageLabel: String {
        switch (includeEnglish, includeKorean) {
        case (true, true): return "English + Korean"
        case (true, false): return "English"
        case (false, true): return "Korean"
        case (false, false): return "None"
        }
    }

    var fetchSummary: String {
        guard hasLanguageSelection else {
            return "Select at least one language."
        }

        switch fetchMode {
        case .newest:
            if includeEnglish && includeKorean {
                return "Fetch up to \(articleCount) newest post(s) per language (EN + KO)"
            }
            return "Fetch up to \(articleCount) newest \(selectedLanguageLabel.lowercased()) post(s)"
        case .recent:
            var text = "Fetch \(selectedLanguageLabel) posts from the last \(sinceHours) hour(s)"
            if articleCount > 0 {
                text += ", max \(articleCount) per language"
            }
            return text
        }
    }

    var pipelineSummary: String {
        var steps = ["Script", "Clip prompts"]
        if runArticleCheck { steps.insert("Article check", at: 1) }
        if runVoiceover { steps.append("Voiceover") }
        if runVideos { steps.append("Veo videos") }
        return steps.joined(separator: " → ")
    }

    var processingLimitSummary: String {
        if resolvedProcessingLimit > 0 {
            return "Run the pipeline on at most \(resolvedProcessingLimit) URL(s) from the fetch list (extra fetched URLs are skipped)."
        }
        return "Run the pipeline on every URL returned by the fetch step."
    }

    func shellArguments() -> [String] {
        var args = ["--date-folder", dateFolderID]

        switch (includeEnglish, includeKorean) {
        case (true, false):
            args += ["--language", "en"]
        case (false, true):
            args += ["--language", "ko"]
        default:
            args += ["--language", "both"]
        }

        switch fetchMode {
        case .newest:
            args += ["--latest", String(articleCount)]
        case .recent:
            args += ["--since-hours", String(sinceHours)]
            if articleCount > 0 {
                args += ["--max-per-index", String(articleCount)]
            }
        }

        if includeProcessed {
            args.append("--include-processed")
        }

        let limit = resolvedProcessingLimit
        if limit > 0 {
            args += ["--limit", String(limit)]
        }

        if !runArticleCheck {
            args.append("--skip-article-check")
        }
        if !runVoiceover {
            args.append("--skip-voiceover")
        }
        if !runVideos {
            args.append("--skip-videos")
        }

        return args
    }
}
