import SwiftUI

struct ScriptReviewView: View {
    let script: String

    var body: some View {
        ScrollView {
            Text(script.isEmpty ? "No script yet." : script)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

struct PromptsView: View {
    let decisions: String
    let clips: [ClipRecord]

    @State private var selection: PromptSection = .decisions

    enum PromptSection: String, CaseIterable, Identifiable {
        case decisions = "Decisions"
        case detailed = "Detailed prompts"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Section", selection: $selection) {
                ForEach(PromptSection.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                switch selection {
                case .decisions:
                    Text(decisions.isEmpty ? "No clip decisions yet." : decisions)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                case .detailed:
                    if clips.isEmpty {
                        Text("No prompts yet.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(clips) { clip in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(clip.label)
                                        .font(.headline)
                                    if let line = clip.scriptLine {
                                        Text(line)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(clip.detailedPrompt ?? clip.veoPrompt ?? "")
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                                Divider()
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
}

struct LogView: View {
    let log: String

    var body: some View {
        ScrollView {
            Text(log.isEmpty ? "No log output yet." : log)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
