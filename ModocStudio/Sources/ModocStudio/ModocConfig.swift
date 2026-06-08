import Foundation

enum ModocConfig {
    private static let rootKey = "modocAIRootPath"
    private static let openedProjectsKey = "openedProjectPaths"
    private static let rootMarkerName = ".modoc-root"

    /// modocAI repo root (contains .env, .venv, scripts/).
    static var rootURL: URL {
        resolvedRootURL()
    }

    /// Call once at launch — picks the best root and saves it if valid.
    static func bootstrap() {
        let root = resolvedRootURL()
        if looksLikeModocRoot(root) {
            setRootURL(root)
            try? ensureProjectsDirectory()
        }
    }

    private static func resolvedRootURL() -> URL {
        if let saved = UserDefaults.standard.string(forKey: rootKey), !saved.isEmpty {
            let url = URL(fileURLWithPath: saved, isDirectory: true)
            if looksLikeModocRoot(url) {
                return url
            }
        }

        if let bundled = bundledModocRoot() {
            return bundled
        }

        if let fromMarker = modocRootFromMarker(near: bundledSearchStart()) {
            return fromMarker
        }

        let documentsDefault = URL(
            fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Documents/modocAI",
            isDirectory: true
        )
        if looksLikeModocRoot(documentsDefault) {
            return documentsDefault
        }

        return bundledModocRoot()
            ?? modocRootFromMarker(near: bundledSearchStart())
            ?? documentsDefault
    }

    private static func bundledSearchStart() -> URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// When ModocStudio.app lives inside the repo (`modocAI/ModocStudio.app`), use that folder.
    static func bundledModocRoot() -> URL? {
        let candidate = bundledSearchStart()
        return looksLikeModocRoot(candidate) ? candidate : nil
    }

    private static func modocRootFromMarker(near url: URL) -> URL? {
        let marker = url.appendingPathComponent(rootMarkerName)
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        return looksLikeModocRoot(root) ? root : nil
    }

    static func looksLikeModocRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        let setup = url.appendingPathComponent("setup.sh")
        let scripts = url.appendingPathComponent("scripts", isDirectory: true)
        return fm.fileExists(atPath: setup.path) || fm.fileExists(atPath: scripts.path)
    }

    static var isRootConfigured: Bool {
        guard let saved = UserDefaults.standard.string(forKey: rootKey) else { return false }
        return !saved.isEmpty && looksLikeModocRoot(URL(fileURLWithPath: saved, isDirectory: true))
    }

    static var rootExists: Bool {
        FileManager.default.fileExists(atPath: rootURL.path)
    }

    /// Ensures `output/projects` exists and is writable.
    static func ensureProjectsDirectory() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        let probe = projectsURL.appendingPathComponent(".modoc-write-test")
        try Data("ok".utf8).write(to: probe)
        try fm.removeItem(at: probe)
    }

    static var canWriteProjects: Bool {
        (try? ensureProjectsDirectory()) != nil
    }

    enum SetupIssue: Equatable {
        case folderMissing(path: String)
        case cannotWriteProjects(path: String)
        case missingVenv

        var message: String {
            switch self {
            case .folderMissing(let path):
                return "modocAI folder not found:\n\(path)\n\nRun ./setup.sh from your modocAI clone, then ./build-modoc-studio.sh."
            case .cannotWriteProjects(let path):
                return "Cannot create or write to:\n\(path)\n\nCheck folder permissions in Finder, or choose another modocAI folder."
            case .missingVenv:
                return "Python environment missing.\n\nFrom Terminal, cd to your modocAI folder and run:\n./setup.sh"
            }
        }
    }

    static var setupIssues: [SetupIssue] {
        var issues: [SetupIssue] = []
        if !rootExists {
            issues.append(.folderMissing(path: rootURL.path))
        } else if !canWriteProjects {
            issues.append(.cannotWriteProjects(path: projectsURL.path))
        }
        if rootExists && !hasVenv {
            issues.append(.missingVenv)
        }
        return issues
    }

    static var needsSetup: Bool {
        !setupIssues.isEmpty
    }

    static var projectsURL: URL {
        rootURL.appendingPathComponent("output/projects", isDirectory: true)
    }

    static func setRootURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        UserDefaults.standard.set(standardized.path, forKey: rootKey)
        let marker = standardized.appendingPathComponent(rootMarkerName)
        try? standardized.path.write(to: marker, atomically: true, encoding: .utf8)
    }

    static var openedProjectPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: openedProjectsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: openedProjectsKey) }
    }

    static func registerOpenedProject(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        var paths = openedProjectPaths
        if !paths.contains(path) {
            paths.insert(path, at: 0)
            openedProjectPaths = paths
        }
    }

    static var pythonURL: URL {
        rootURL.appendingPathComponent(".venv/bin/python")
    }

    static var hasVenv: Bool {
        FileManager.default.fileExists(atPath: pythonURL.path)
    }

    static var hasAPIKey: Bool {
        let env = rootURL.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: env, encoding: .utf8) else { return false }
        return text.contains(where: { _ in true })
            && text.range(of: #"GEMINI_API_KEY=\S+"#, options: .regularExpression) != nil
    }
}
