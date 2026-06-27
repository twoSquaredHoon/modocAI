import Foundation
import SwiftUI

enum ScriptVerificationVerdict: String, Codable {
    case pass
    case review
    case fail

    var label: String {
        switch self {
        case .pass: return "Pass"
        case .review: return "Review"
        case .fail: return "Fail"
        }
    }

    var color: Color {
        switch self {
        case .pass: return .green
        case .review: return .orange
        case .fail: return .red
        }
    }

    var icon: String {
        switch self {
        case .pass: return "checkmark.seal.fill"
        case .review: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }
}

enum IssueSeverity: String {
    case high, medium, low, unknown

    init(_ raw: String?) {
        switch raw?.lowercased() {
        case "high": self = .high
        case "medium": self = .medium
        case "low": self = .low
        default: self = .unknown
        }
    }

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .unknown: return .secondary
        }
    }

    var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unknown: return "Issue"
        }
    }
}

struct ScriptLineIssue: Codable, Hashable, Identifiable {
    var id: String { (kind ?? "") + (severity ?? "") + (note ?? "") }
    let kind: String?
    let severity: String?
    let note: String?

    var issueSeverity: IssueSeverity { IssueSeverity(severity) }
}

struct ScriptLineCheck: Codable, Hashable, Identifiable {
    var id: String { lineID ?? lineText ?? UUID().uuidString }
    let lineID: String?
    let lineText: String?
    let status: String?
    let issues: [ScriptLineIssue]?

    enum CodingKeys: String, CodingKey {
        case lineID = "line_id"
        case lineText = "line_text"
        case status, issues
    }

    var hasIssue: Bool {
        status?.lowercased() == "issue" || !(issues?.isEmpty ?? true)
    }

    var highestSeverity: IssueSeverity {
        let levels = (issues ?? []).map { IssueSeverity($0.severity) }
        if levels.contains(.high) { return .high }
        if levels.contains(.medium) { return .medium }
        if levels.contains(.low) { return .low }
        return hasIssue ? .unknown : .unknown
    }
}

struct ScriptVerificationIssue: Codable, Identifiable, Hashable {
    var id: String { (claim ?? fact ?? UUID().uuidString) + (severity ?? "") + (lineID ?? "") }
    let claim: String?
    let fact: String?
    let severity: String?
    let note: String?
    let lineID: String?

    enum CodingKeys: String, CodingKey {
        case claim, fact, severity, note
        case lineID = "line_id"
    }

    var title: String { claim ?? fact ?? "" }
    var issueSeverity: IssueSeverity { IssueSeverity(severity) }
}

struct ScriptVerificationAgeCheck: Codable, Hashable {
    let ok: Bool?
    let articleAge: String?
    let scriptAge: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case articleAge = "article_age"
        case scriptAge = "script_age"
        case note
    }
}

struct ScriptVerificationReport: Codable, Hashable {
    let verdict: ScriptVerificationVerdict
    let summary: String
    let scriptLineChecks: [ScriptLineCheck]
    let supportedClaims: [String]
    let unsupportedOrInvented: [ScriptVerificationIssue]
    let importantOmissions: [ScriptVerificationIssue]
    let ageConsistency: ScriptVerificationAgeCheck?
    let recommendedFixes: [String]
    let verifiedAt: String?
    let sourceURL: String?
    let language: String?

    enum CodingKeys: String, CodingKey {
        case verdict, summary
        case scriptLineChecks = "script_line_checks"
        case supportedClaims = "supported_claims"
        case unsupportedOrInvented = "unsupported_or_invented"
        case importantOmissions = "important_omissions"
        case ageConsistency = "age_consistency"
        case recommendedFixes = "recommended_fixes"
        case verifiedAt = "verified_at"
        case sourceURL = "source_url"
        case language
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try c.decode(ScriptVerificationVerdict.self, forKey: .verdict)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        scriptLineChecks = try c.decodeIfPresent([ScriptLineCheck].self, forKey: .scriptLineChecks) ?? []
        supportedClaims = try c.decodeIfPresent([String].self, forKey: .supportedClaims) ?? []
        unsupportedOrInvented = try c.decodeIfPresent([ScriptVerificationIssue].self, forKey: .unsupportedOrInvented) ?? []
        importantOmissions = try c.decodeIfPresent([ScriptVerificationIssue].self, forKey: .importantOmissions) ?? []
        ageConsistency = try c.decodeIfPresent(ScriptVerificationAgeCheck.self, forKey: .ageConsistency)
        recommendedFixes = try c.decodeIfPresent([String].self, forKey: .recommendedFixes) ?? []
        verifiedAt = try c.decodeIfPresent(String.self, forKey: .verifiedAt)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        language = try c.decodeIfPresent(String.self, forKey: .language)
    }
}

struct AnnotatedScriptLine: Identifiable, Hashable {
    let line: ScriptLine
    let check: ScriptLineCheck?
    let linkedIssues: [ScriptVerificationIssue]
    let isDisregarded: Bool

    var id: String { line.id }

    init(
        line: ScriptLine,
        check: ScriptLineCheck?,
        linkedIssues: [ScriptVerificationIssue],
        isDisregarded: Bool = false
    ) {
        self.line = line
        self.check = check
        self.linkedIssues = linkedIssues
        self.isDisregarded = isDisregarded
    }

    var hasIssue: Bool {
        check?.hasIssue == true || !linkedIssues.isEmpty
    }

    var hasActiveIssue: Bool {
        hasIssue && !isDisregarded
    }

    var lineIssues: [ScriptLineIssue] {
        check?.issues ?? []
    }

    var highestSeverity: IssueSeverity {
        let fromLine = check?.highestSeverity ?? .unknown
        let fromLinked = linkedIssues.map(\.issueSeverity)
        if fromLine == .high || fromLinked.contains(.high) { return .high }
        if fromLine == .medium || fromLinked.contains(.medium) { return .medium }
        if fromLine == .low || fromLinked.contains(.low) { return .low }
        return hasIssue ? .unknown : .unknown
    }
}

struct ScriptVerificationOverrides: Codable {
    var verifiedAt: String
    var disregardedLineIDs: [String]

    enum CodingKeys: String, CodingKey {
        case verifiedAt = "verified_at"
        case disregardedLineIDs = "disregarded_line_ids"
    }
}

extension ScriptVerificationReport {
    func annotate(lines: [ScriptLine], disregarded: Set<String> = []) -> [AnnotatedScriptLine] {
        let checksByID = Dictionary(
            uniqueKeysWithValues: scriptLineChecks.compactMap { check -> (String, ScriptLineCheck)? in
                guard let id = check.lineID else { return nil }
                return (id, check)
            }
        )

        return lines.map { line in
            let check = checksByID[line.id]
            let linked = unsupportedOrInvented.filter { issue in
                if issue.lineID == line.id { return true }
                guard let claim = issue.claim?.lowercased(), !claim.isEmpty else { return false }
                let text = line.text.lowercased()
                return text.contains(claim) || claim.contains(text)
            }
            return AnnotatedScriptLine(
                line: line,
                check: check,
                linkedIssues: linked,
                isDisregarded: disregarded.contains(line.id)
            )
        }
    }

    func activeIssueLineCount(in lines: [ScriptLine], disregarded: Set<String>) -> Int {
        annotate(lines: lines, disregarded: disregarded).filter(\.hasActiveIssue).count
    }

    var issueLineCount: Int {
        scriptLineChecks.filter(\.hasIssue).count
    }
}

extension VideoProject {
    var scriptVerificationJSONURL: URL {
        folderURL.appendingPathComponent("script_verification.json")
    }

    var scriptVerificationTextURL: URL {
        folderURL.appendingPathComponent("script_verification.txt")
    }

    var scriptVerificationOverridesURL: URL {
        folderURL.appendingPathComponent("script_verification_overrides.json")
    }

    var sourceArticleURL: URL {
        folderURL.appendingPathComponent("source_article.txt")
    }

    var hasScriptVerification: Bool {
        FileManager.default.fileExists(atPath: scriptVerificationJSONURL.path)
    }

    func loadScriptVerification() -> ScriptVerificationReport? {
        guard let data = try? Data(contentsOf: scriptVerificationJSONURL),
              let report = try? JSONDecoder().decode(ScriptVerificationReport.self, from: data) else {
            return nil
        }
        return report
    }

    func loadScriptVerificationText() -> String {
        (try? String(contentsOf: scriptVerificationTextURL, encoding: .utf8)) ?? ""
    }

    func loadSourceArticle() -> String {
        (try? String(contentsOf: sourceArticleURL, encoding: .utf8)) ?? ""
    }

    func loadVerificationOverrides(for report: ScriptVerificationReport) -> Set<String> {
        guard let data = try? Data(contentsOf: scriptVerificationOverridesURL),
              let overrides = try? JSONDecoder().decode(ScriptVerificationOverrides.self, from: data),
              overrides.verifiedAt == (report.verifiedAt ?? "") else {
            return []
        }
        return Set(overrides.disregardedLineIDs)
    }

    func saveVerificationOverrides(_ overrides: ScriptVerificationOverrides) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(overrides)
        try data.write(to: scriptVerificationOverridesURL, options: .atomic)
        try LanguageWorkspace.persistActive(self, language: manifest.language)
    }

    func clearVerificationOverrides() throws {
        if FileManager.default.fileExists(atPath: scriptVerificationOverridesURL.path) {
            try FileManager.default.removeItem(at: scriptVerificationOverridesURL)
        }
    }
}
