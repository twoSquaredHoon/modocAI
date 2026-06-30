import Foundation

enum BatchRunner {
    private static func shellEscape(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    @discardableResult
    static func launchDetached(shellCommand: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", shellCommand]
        process.standardOutput = nil
        process.standardError = nil
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func batchDir(for dateFolderID: String) -> URL {
        ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
    }

    static func logURL(for dateFolderID: String, filename: String = "daily-batch-run.log") -> URL {
        batchDir(for: dateFolderID).appendingPathComponent(filename)
    }

    static func todayFolderID() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func customFolderID() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-'custom'-HHmm"
        return f.string(from: Date())
    }

    static func startDailyBatch(dateFolderID: String) throws {
        guard !BatchStateReader.isProcessRunning(for: dateFolderID) else {
            throw BatchRunnerError.alreadyRunning
        }

        let root = shellEscape(ModocConfig.rootURL.path)
        let batchDirPath = shellEscape(batchDir(for: dateFolderID).path)
        let log = shellEscape(logURL(for: dateFolderID).path)

        let cmd = """
        mkdir -p '\(batchDirPath)' && \
        cd '\(root)' && \
        export PYTHONUNBUFFERED=1 && \
        nohup ./daily-batch.sh >> '\(log)' 2>&1 &
        """
        guard try launchDetached(shellCommand: cmd) else {
            throw BatchRunnerError.launchFailed
        }
    }

    static func startCustomBatch(options: CustomBatchOptions) throws {
        let dateFolderID = options.dateFolderID
        guard !BatchStateReader.isProcessRunning(for: dateFolderID) else {
            throw BatchRunnerError.alreadyRunning
        }

        let root = shellEscape(ModocConfig.rootURL.path)
        let batchDirPath = shellEscape(batchDir(for: dateFolderID).path)
        let log = shellEscape(logURL(for: dateFolderID, filename: "custom-batch-run.log").path)
        let args = options.shellArguments().map { shellEscape($0) }.joined(separator: " ")

        let cmd = """
        mkdir -p '\(batchDirPath)' && \
        cd '\(root)' && \
        export PYTHONUNBUFFERED=1 && \
        nohup ./custom-batch.sh \(args) >> '\(log)' 2>&1 &
        """
        guard try launchDetached(shellCommand: cmd) else {
            throw BatchRunnerError.launchFailed
        }
    }

    static func resumeDailyBatch(dateFolderID: String) throws {
        guard !BatchStateReader.isProcessRunning(for: dateFolderID) else {
            throw BatchRunnerError.alreadyRunning
        }

        let root = shellEscape(ModocConfig.rootURL.path)
        let batchDirPath = shellEscape(Self.batchDir(for: dateFolderID).path)
        let log = shellEscape(logURL(for: dateFolderID).path)

        let script: String
        if FileManager.default.fileExists(atPath: Self.batchDir(for: dateFolderID).appendingPathComponent("urls.txt").path) {
            script = "./resume-batch.sh '\(shellEscape(dateFolderID))'"
        } else {
            script = "./daily-batch.sh"
        }

        let cmd = """
        mkdir -p '\(batchDirPath)' && \
        cd '\(root)' && \
        export PYTHONUNBUFFERED=1 && \
        nohup \(script) >> '\(log)' 2>&1 &
        """
        guard try launchDetached(shellCommand: cmd) else {
            throw BatchRunnerError.launchFailed
        }
    }
}

enum BatchRunnerError: LocalizedError {
    case alreadyRunning
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A batch is already running for this date."
        case .launchFailed:
            return "Could not start the batch process."
        }
    }
}
