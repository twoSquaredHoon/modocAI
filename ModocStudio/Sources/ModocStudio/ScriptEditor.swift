import Foundation

enum ScriptEditError: LocalizedError {
    case lineNotFound(String)
    case pipelineBusy
    case editResultMissing

    var errorDescription: String? {
        switch self {
        case .lineNotFound(let id):
            return "Could not find script line \(id)."
        case .pipelineBusy:
            return "Wait for the current pipeline step to finish."
        case .editResultMissing:
            return "Rewrite finished but no result was saved."
        }
    }
}

struct ScriptLineEditResult: Codable {
    let action: String
    let lineID: String
    let oldLine: String
    let newLine: String

    enum CodingKeys: String, CodingKey {
        case action
        case lineID = "line_id"
        case oldLine = "old_line"
        case newLine = "new_line"
    }
}

enum ScriptEditor {
    private static let sectionHeaders: Set<String> = ["HOOK", "BODY", "RELIEF", "CTA"]

    static func removeLine(lineID: String, from script: String) -> String? {
        applyEdit(lineID: lineID, in: script) { _ in nil }
    }

    static func replaceLine(lineID: String, in script: String, with newText: String) -> String? {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return applyEdit(lineID: lineID, in: script) { _ in trimmed }
    }

    private static func applyEdit(
        lineID: String,
        in script: String,
        transform: (String) -> String?
    ) -> String? {
        var section = ScriptSection.other
        var sectionLineIndex = 0
        var output: [String] = []
        var found = false

        for raw in script.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                output.append(line)
                continue
            }

            if let detected = detectSectionHeader(trimmed) {
                section = detected
                sectionLineIndex = 0
                output.append(line)
                continue
            }

            sectionLineIndex += 1
            let id = "\(section.rawValue)-\(sectionLineIndex)"

            if id == lineID {
                found = true
                if let replacement = transform(trimmed) {
                    output.append(replacement)
                }
                continue
            }

            output.append(line)
        }

        guard found else { return nil }

        var joined = output.joined(separator: "\n")
        if !joined.hasSuffix("\n") {
            joined += "\n"
        }
        return joined
    }

    private static func detectSectionHeader(_ line: String) -> ScriptSection? {
        let normalized = line
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        switch normalized {
        case "HOOK": return .hook
        case "BODY": return .body
        case "RELIEF": return .relief
        case "CTA": return .cta
        default: return nil
        }
    }
}

extension VideoProject {
    var lastScriptLineEditURL: URL {
        folderURL.appendingPathComponent(".last_script_line_edit.json")
    }

    func saveScript(_ text: String) throws {
        try text.write(to: scriptURL, atomically: true, encoding: .utf8)
        try LanguageWorkspace.persistActive(self, language: manifest.language)
    }

    func clearScriptVerificationFiles() throws {
        for url in [scriptVerificationJSONURL, scriptVerificationTextURL, scriptVerificationOverridesURL] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func loadLastScriptLineEdit() -> ScriptLineEditResult? {
        guard let data = try? Data(contentsOf: lastScriptLineEditURL),
              let result = try? JSONDecoder().decode(ScriptLineEditResult.self, from: data) else {
            return nil
        }
        return result
    }
}
