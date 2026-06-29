import Foundation

struct BatchCurrentJob: Codable, Hashable {
    var index: Int
    var url: String
    var language: String
    var folder: String?
    var step: String
}

struct BatchStateFile: Codable, Hashable {
    var version: Int
    var status: String
    var batchDir: String?
    var urlsFile: String?
    var startedAt: String?
    var updatedAt: String?
    var finishedAt: String?
    var pid: Int?
    var resume: Bool?
    var total: Int
    var completed: Int
    var failed: Int
    var skipped: Int
    var current: BatchCurrentJob?
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case version, status, pid, resume, total, completed, failed, skipped, current
        case batchDir = "batch_dir"
        case urlsFile = "urls_file"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case finishedAt = "finished_at"
        case lastError = "last_error"
    }

    var effectiveStatus: BatchEffectiveStatus {
        if status == "running" {
            if let pid, BatchStateReader.isProcessAlive(pid: pid) {
                return .running
            }
            if let updatedAt, BatchStateReader.secondsSince(iso: updatedAt) ?? 0 > 900 {
                return .interrupted
            }
            return .interrupted
        }
        if status == "completed" { return .completed }
        if status == "failed" { return .failed }
        return .idle
    }

    var progressLabel: String {
        let done = completed + failed + skipped
        return "\(done)/\(total)"
    }
}

enum BatchEffectiveStatus: String {
    case idle
    case running
    case completed
    case failed
    case interrupted

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Finished with errors"
        case .interrupted: return "Interrupted"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle.dashed"
        case .running: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .interrupted: return "pause.circle.fill"
        }
    }

    var tint: String {
        switch self {
        case .running: return "orange"
        case .completed: return "green"
        case .failed, .interrupted: return "red"
        default: return "secondary"
        }
    }
}

struct InferredBatchProgress {
    var total: Int
    var ready: Int
    var failed: Int
    var inProgress: Int

    var finishedCount: Int { ready + failed + inProgress }
    var needsResume: Bool { finishedCount < total || inProgress > 0 }
    var isComplete: Bool { !needsResume && inProgress == 0 && ready + failed >= total }
}

enum BatchStateReader {
    static func load(from batchFolderURL: URL) -> BatchStateFile? {
        let url = batchFolderURL.appendingPathComponent("batch_state.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(BatchStateFile.self, from: data) else {
            return nil
        }
        return file
    }

    static func hasBatchActivity(in batchFolderURL: URL) -> Bool {
        let state = batchFolderURL.appendingPathComponent("batch_state.json")
        if FileManager.default.fileExists(atPath: state.path) { return true }
        return hasBatchURLs(in: batchFolderURL)
    }

    static func hasBatchURLs(in batchFolderURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: batchFolderURL.appendingPathComponent("urls.txt").path)
    }

    static func inferProgress(in batchFolderURL: URL, projects: [VideoProject]) -> InferredBatchProgress? {
        let urlsFile = batchFolderURL.appendingPathComponent("urls.txt")
        guard let text = try? String(contentsOf: urlsFile, encoding: .utf8) else { return nil }
        let total = text.split(separator: "\n").filter { line in
            let trimmed = line.split(separator: "#", maxSplits: 1)[0].trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("http")
        }.count
        guard total > 0 else { return nil }

        var ready = 0
        var failed = 0
        var inProgress = 0
        for project in projects {
            switch project.manifest.phase {
            case .ready: ready += 1
            case .failed: failed += 1
            default: inProgress += 1
            }
        }
        return InferredBatchProgress(total: total, ready: ready, failed: failed, inProgress: inProgress)
    }

    static func isProcessAlive(pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0
    }

    static func secondsSince(iso: String) -> Double? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return Date().timeIntervalSince(date)
    }

    static func isProcessRunning(for dateFolderID: String) -> Bool {
        let folder = ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
        guard let state = load(from: folder) else { return false }
        guard state.effectiveStatus == .running, let pid = state.pid else { return false }
        return isProcessAlive(pid: pid)
    }

    static func formatRelative(iso: String?) -> String {
        guard let iso, let seconds = secondsSince(iso: iso) else { return "—" }
        let mins = Int(seconds / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }
}
