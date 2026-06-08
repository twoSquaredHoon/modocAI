import Foundation

enum ProjectPhase: String, Codable {
    case creatingScript
    case scriptReview
    case generatingPrompts
    case promptsReview
    case generatingVoiceover
    case voiceoverReview
    case generatingVideos
    case ready
    case failed
}

enum ProjectLanguage: String, Codable, CaseIterable, Hashable {
    case en
    case ko
    case es

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ko: return "한국어 (Korean)"
        case .es: return "Español (Spanish)"
        }
    }

    var shortLabel: String {
        switch self {
        case .en: return "EN"
        case .ko: return "KO"
        case .es: return "ES"
        }
    }
}

struct ProjectManifest: Codable, Hashable {
    var id: String
    var title: String
    var blogURL: String
    var createdAt: String
    var phase: ProjectPhase
    var language: ProjectLanguage
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case blogURL = "blog_url"
        case createdAt = "created_at"
        case phase
        case language
        case lastError = "last_error"
    }

    init(
        id: String,
        title: String,
        blogURL: String,
        createdAt: String,
        phase: ProjectPhase,
        language: ProjectLanguage = .en,
        lastError: String?
    ) {
        self.id = id
        self.title = title
        self.blogURL = blogURL
        self.createdAt = createdAt
        self.phase = phase
        self.language = language
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        blogURL = try container.decode(String.self, forKey: .blogURL)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        phase = try container.decode(ProjectPhase.self, forKey: .phase)
        language = try container.decodeIfPresent(ProjectLanguage.self, forKey: .language) ?? .en
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct ClipRecord: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let detailedPrompt: String?
    let veoPrompt: String?
    let durationSeconds: Int?
    let scriptLine: String?

    enum CodingKeys: String, CodingKey {
        case id, label
        case detailedPrompt = "detailed_prompt"
        case veoPrompt = "veo_prompt"
        case durationSeconds = "duration_seconds"
        case scriptLine = "script_line"
    }
}

struct ClipsFile: Codable {
    let clips: [ClipRecord]
}

struct VideoProject: Identifiable, Hashable {
    let id: String
    let folderURL: URL
    var manifest: ProjectManifest

    var scriptURL: URL { folderURL.appendingPathComponent("script.txt") }
    var decisionsURL: URL { folderURL.appendingPathComponent("clip_decisions.txt") }
    var promptsURL: URL { folderURL.appendingPathComponent("clip_prompts.txt") }
    var clipsJSONURL: URL { folderURL.appendingPathComponent("clips.json") }
    var logURL: URL { folderURL.appendingPathComponent("pipeline.log") }
    var voiceoverURL: URL { folderURL.appendingPathComponent("voiceover.wav") }
    var speechURL: URL { folderURL.appendingPathComponent("speech.txt") }
    var voiceoverMetaURL: URL { folderURL.appendingPathComponent("voiceover_meta.json") }
    var videosURL: URL { folderURL.appendingPathComponent("videos", isDirectory: true) }

    func videoURL(for clipID: String) -> URL {
        videosURL.appendingPathComponent("\(clipID).mp4")
    }

    var hasScript: Bool {
        FileManager.default.fileExists(atPath: scriptURL.path)
    }

    var hasClipsJSON: Bool {
        FileManager.default.fileExists(atPath: clipsJSONURL.path)
    }

    var hasVoiceover: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: voiceoverURL.path),
              let size = attrs[.size] as? Int else { return false }
        return size > 1000
    }

    func loadScript() -> String {
        (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
    }

    func loadDecisions() -> String {
        (try? String(contentsOf: decisionsURL, encoding: .utf8)) ?? ""
    }

    func loadClips() -> [ClipRecord] {
        guard let data = try? Data(contentsOf: clipsJSONURL),
              let file = try? JSONDecoder().decode(ClipsFile.self, from: data) else {
            return []
        }
        return file.clips.sorted { Self.sortKey(for: $0.id) < Self.sortKey(for: $1.id) }
    }

    static func sortKey(for id: String) -> (Int, Int) {
        if id == "hook" { return (0, 0) }
        if id.hasPrefix("body_"), let n = Int(id.dropFirst(5)) { return (1, n) }
        if id.hasPrefix("explain_"), let n = Int(id.dropFirst(8)) { return (2, n) }
        if id.hasPrefix("signs_"), let n = Int(id.dropFirst(6)) { return (3, n) }
        if id == "relief" { return (4, 0) }
        if id == "cta" { return (5, 0) }
        return (99, 0)
    }

    func clipSortKey(_ id: String) -> (Int, Int) {
        Self.sortKey(for: id)
    }

    func videoStatus(for clips: [ClipRecord]) -> (done: Int, total: Int) {
        let total = clips.count
        let done = clips.filter { clip in
            let path = videoURL(for: clip.id)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
                  let size = attrs[.size] as? Int else { return false }
            return size > 1000
        }.count
        return (done, total)
    }

    static func slug(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "project" }
        let last = url.pathComponents.last ?? "project"
        let cleaned = last.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\-]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(cleaned.prefix(50)).isEmpty ? "project" : String(cleaned.prefix(50))
    }

    static func title(from script: String) -> String {
        for line in script.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if t.uppercased().hasSuffix(":") && t.count < 20 { continue }
            return String(t.prefix(72))
        }
        return "Untitled project"
    }
}
