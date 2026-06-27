import SwiftUI

struct ScriptReviewView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject
    let script: String
    let clips: [ClipRecord]

    @State private var selectedLineIDs: Set<String> = []
    @State private var isCreating = false
    @State private var actionError: String?
    @State private var lastCreatedClipID: String?
    @State private var confirmVideo = false

    private var lines: [ScriptLine] { ScriptParser.parse(script) }

    private var selectedLines: [ScriptLine] {
        lines.filter { selectedLineIDs.contains($0.id) }
    }

    private var current: VideoProject {
        store.selectedProject ?? project
    }

    var body: some View {
        VStack(spacing: 0) {
            if script.isEmpty {
                ContentUnavailableView(
                    "No script yet",
                    systemImage: "doc.text",
                    description: Text("Generate a script from the Workflow tab.")
                )
            } else {
                scriptToolbar
                Divider()

                if lines.isEmpty {
                    ScrollView {
                        Text(script)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    selectionToolbar
                    Divider()
                    scriptList
                }
            }
        }
        .alert("Could not create clip", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog(
            "Generate Veo video for this clip?",
            isPresented: $confirmVideo,
            titleVisibility: .visible
        ) {
            Button("Prompt + video (Veo, paid)") {
                Task { await createClip(generateVideo: true) }
            }
            Button("Prompt only (free)") {
                Task { await createClip(generateVideo: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedLines.count) line(s) selected. Prompt-only adds the clip to Clips; you can generate video later.")
        }
    }

    private var scriptToolbar: some View {
        HStack(spacing: 12) {
            Text("Select lines to create custom clips")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if isCreating || store.pipeline.isRunning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Text("\(selectedLineIDs.count) of \(lines.count) lines selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !selectedLineIDs.isEmpty {
                Button("Clear") { selectedLineIDs.removeAll() }
                    .buttonStyle(.borderless)
            }

            Spacer()

            if isCreating || store.pipeline.isRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                confirmVideo = true
            } label: {
                Label("Create clip from selection", systemImage: "film.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedLineIDs.isEmpty || isCreating || store.pipeline.isRunning)

            if let clipID = lastCreatedClipID {
                Text("Created \(clipID)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var scriptList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedSections, id: \.section) { group in
                    sectionBlock(group)
                }
            }
            .padding()
        }
    }

    private struct SectionGroup {
        let section: ScriptSection
        let lines: [ScriptLine]
    }

    private var groupedSections: [SectionGroup] {
        var order: [ScriptSection] = []
        var buckets: [ScriptSection: [ScriptLine]] = [:]
        for line in lines {
            if buckets[line.section] == nil {
                order.append(line.section)
                buckets[line.section] = []
            }
            buckets[line.section]?.append(line)
        }
        return order.map { SectionGroup(section: $0, lines: buckets[$0] ?? []) }
    }

    @ViewBuilder
    private func sectionBlock(_ group: SectionGroup) -> some View {
        Text(group.section.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)

        ForEach(group.lines) { line in
            lineRow(line)
        }
    }

    private func lineRow(_ line: ScriptLine) -> some View {
        let isSelected = selectedLineIDs.contains(line.id)
        let linkedClips = ScriptParser.clipIDs(for: line, in: clips)

        return Button {
            toggleSelection(line.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.body)

                Text(line.text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !linkedClips.isEmpty {
                    Image(systemName: "film.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .help("Clip: \(linkedClips.joined(separator: ", "))")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isCreating || store.pipeline.isRunning)
    }

    private func toggleSelection(_ id: String) {
        if selectedLineIDs.contains(id) {
            selectedLineIDs.remove(id)
        } else {
            selectedLineIDs.insert(id)
        }
    }

    @MainActor
    private func createClip(generateVideo: Bool) async {
        isCreating = true
        defer { isCreating = false }

        let texts = selectedLines.map(\.text)
        do {
            let clipID = try await store.createCustomClip(
                current,
                lines: texts,
                generateVideo: generateVideo
            )
            lastCreatedClipID = clipID
            selectedLineIDs.removeAll()
            store.refreshProjects()
        } catch {
            actionError = error.localizedDescription
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
