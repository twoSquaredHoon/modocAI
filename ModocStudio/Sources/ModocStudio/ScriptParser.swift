import Foundation

enum ScriptSection: String, CaseIterable {
    case hook = "HOOK"
    case body = "BODY"
    case relief = "RELIEF"
    case cta = "CTA"
    case other = "OTHER"
}

struct ScriptLine: Identifiable, Hashable {
    let id: String
    let section: ScriptSection
    let text: String
}

enum ScriptParser {
    private static let sectionHeaders: [(ScriptSection, String)] = [
        (.hook, "HOOK"),
        (.body, "BODY"),
        (.relief, "RELIEF"),
        (.cta, "CTA"),
    ]

    static func parse(_ script: String) -> [ScriptLine] {
        var section: ScriptSection = .other
        var sectionLineIndex = 0
        var result: [ScriptLine] = []

        for raw in script.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }

            if let detected = detectSectionHeader(line) {
                section = detected
                sectionLineIndex = 0
                continue
            }

            sectionLineIndex += 1
            let id = "\(section.rawValue)-\(sectionLineIndex)"
            result.append(ScriptLine(id: id, section: section, text: line))
        }
        return result
    }

    private static func detectSectionHeader(_ line: String) -> ScriptSection? {
        let normalized = line
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        for (section, label) in sectionHeaders {
            if normalized == label { return section }
        }
        return nil
    }

    /// Lines already used by a clip (exact or substring match on script_line).
    static func clipIDs(for line: ScriptLine, in clips: [ClipRecord]) -> [String] {
        clips.compactMap { clip in
            guard let scriptLine = clip.scriptLine?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !scriptLine.isEmpty else { return nil }
            if scriptLine == line.text { return clip.id }
            if scriptLine.contains(line.text) || line.text.contains(scriptLine) { return clip.id }
            return nil
        }
    }
}
