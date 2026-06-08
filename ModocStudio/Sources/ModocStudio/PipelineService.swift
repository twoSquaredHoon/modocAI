import Foundation

@MainActor
final class PipelineService: ObservableObject {
    @Published var logText = ""
    @Published var isRunning = false
    @Published var runningStep: PipelineStep?

    func appendLog(_ chunk: String) {
        logText += chunk
    }

    func clearLog() {
        logText = ""
    }

    func runProjectStep(_ project: VideoProject, step: PipelineStep) async throws {
        isRunning = true
        runningStep = step
        clearLog()
        defer {
            isRunning = false
            runningStep = nil
        }

        appendLog("=== \(step.title) ===\n")

        switch step {
        case .generateScript:
            try await runPython(
                script: "scripts/blog_to_script.py",
                args: [
                    project.manifest.blogURL,
                    "--output", project.scriptURL.path,
                    "--language", project.manifest.language.rawValue,
                ]
            )
        case .generatePrompts:
            try await runPython(
                script: "scripts/script_to_clips.py",
                args: [
                    project.scriptURL.path,
                    "--output-dir", project.folderURL.path,
                    "--prompts-only",
                    "--language", project.manifest.language.rawValue,
                ]
            )
            try await runPython(
                script: "scripts/derived_clips.py",
                args: [
                    project.folderURL.path,
                    project.scriptURL.path,
                    "--language", project.manifest.language.rawValue,
                ]
            )
        case .generateVideos:
            try await runPython(
                script: "scripts/script_to_clips.py",
                args: ["--resume", project.folderURL.path]
            )
        case .generateVoiceover:
            try await runPython(
                script: "scripts/script_to_voiceover.py",
                args: [
                    project.scriptURL.path,
                    "--output", project.voiceoverURL.path,
                    "--clips-dir", project.folderURL.path,
                    "--language", project.manifest.language.rawValue,
                ]
            )
        case .regenerateClip(let clipId):
            try await runPython(
                script: "scripts/script_to_clips.py",
                args: ["--resume", project.folderURL.path, "--only", clipId]
            )
        case .regenerateAllClips:
            try await runPython(
                script: "scripts/script_to_clips.py",
                args: ["--resume", project.folderURL.path]
            )
        }

        try appendToProjectLog(project: project)
    }

    private func appendToProjectLog(project: VideoProject) throws {
        let chunk = "\n--- \(ISO8601DateFormatter().string(from: Date())) ---\n\(logText)\n"
        if FileManager.default.fileExists(atPath: project.logURL.path) {
            let handle = try FileHandle(forWritingTo: project.logURL)
            handle.seekToEndOfFile()
            handle.write(Data(chunk.utf8))
            try handle.close()
        } else {
            try chunk.write(to: project.logURL, atomically: true, encoding: .utf8)
        }
    }

    enum PipelineStep: Equatable {
        case generateScript
        case generatePrompts
        case generateVoiceover
        case generateVideos
        case regenerateClip(String)
        case regenerateAllClips

        var title: String {
            switch self {
            case .generateScript: return "Blog → Script"
            case .generatePrompts: return "Script → Clip prompts"
            case .generateVoiceover: return "Script → Voiceover"
            case .generateVideos: return "Generate Veo videos"
            case .regenerateClip(let id): return "Regenerate clip: \(id)"
            case .regenerateAllClips: return "Regenerate all clips"
            }
        }
    }

    private func runPython(script: String, args: [String]) async throws {
        let root = ModocConfig.rootURL
        let python = ModocConfig.pythonURL

        guard FileManager.default.fileExists(atPath: python.path) else {
            throw PipelineError.missingVenv
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = python
            process.arguments = [root.appendingPathComponent(script).path] + args
            process.currentDirectoryURL = root

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    self.appendLog(text)
                }
            }

            process.terminationHandler = { proc in
                handle.readabilityHandler = nil
                let code = proc.terminationStatus
                if code == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PipelineError.exitCode(Int(code)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum PipelineError: LocalizedError {
    case missingVenv
    case exitCode(Int)

    var errorDescription: String? {
        switch self {
        case .missingVenv:
            return "Python venv not found. Run ./setup.sh in the modocAI folder."
        case .exitCode(let code):
            return "Pipeline step failed (exit \(code)). See log for details."
        }
    }
}
