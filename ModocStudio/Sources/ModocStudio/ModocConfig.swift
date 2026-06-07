import Foundation

enum ModocConfig {
    private static let rootKey = "modocAIRootPath"
    private static let openedProjectsKey = "openedProjectPaths"

    /// modocAI repo root (contains .env, .venv, scripts/).
    static var rootURL: URL {
        if let saved = UserDefaults.standard.string(forKey: rootKey), !saved.isEmpty {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        // Default for this machine; override in Settings if needed.
        return URL(fileURLWithPath: "/Users/seunghoon/Documents/2.Area/modocAI", isDirectory: true)
    }

    static var projectsURL: URL {
        rootURL.appendingPathComponent("output/projects", isDirectory: true)
    }

    static func setRootURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: rootKey)
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
