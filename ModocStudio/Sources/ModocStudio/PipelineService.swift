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
        case .createCustomClip(let linesFile, let generateVideo):
            var args = [
                project.folderURL.path,
                "--lines-file", linesFile.path,
                "--language", project.manifest.language.rawValue,
            ]
            if generateVideo {
                args.append("--generate-video")
            }
            try await runPython(script: "scripts/create_custom_clip.py", args: args)
        case .verifyScript:
            try await runPython(
                script: "scripts/compare_script_to_article.py",
                args: [
                    project.scriptURL.path,
                    "--url", project.manifest.blogURL,
                    "--output-dir", project.folderURL.path,
                    "--language", project.manifest.language.rawValue,
                ]
            )
        case .rewriteScriptLine(let lineID):
            try await runPython(
                script: "scripts/rewrite_script_line.py",
                args: [
                    project.scriptURL.path,
                    "--line-id", lineID,
                    "--output-dir", project.folderURL.path,
                    "--language", project.manifest.language.rawValue,
                ]
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
        case createCustomClip(linesFile: URL, generateVideo: Bool)
        case verifyScript
        case rewriteScriptLine(String)

        var title: String {
            switch self {
            case .generateScript: return "Blog → Script"
            case .generatePrompts: return "Script → Clip prompts"
            case .generateVoiceover: return "Script → Voiceover"
            case .generateVideos: return "Generate Veo videos"
            case .regenerateClip(let id): return "Regenerate clip: \(id)"
            case .regenerateAllClips: return "Regenerate all clips"
            case .createCustomClip: return "Create custom clip"
            case .verifyScript: return "Script vs article"
            case .rewriteScriptLine(let id): return "Rewrite script line \(id)"
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
    case missingSetup
    case cannotWriteProjects
    case exitCode(Int)

    var errorDescription: String? {
        switch self {
        case .missingVenv:
            return "Python venv not found. Run ./setup.sh in the modocAI folder."
        case .missingSetup:
            return "Modoc Studio is not set up yet. Choose your modocAI folder first."
        case .cannotWriteProjects:
            return "Cannot save projects. Choose your modocAI folder or fix output/projects permissions."
        case .exitCode(let code):
            return "Pipeline step failed (exit \(code)). See log for details."
        }
    }
}
