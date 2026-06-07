import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    @State private var tab: DetailTab = .workflow
    @State private var selectedClipID: String?
    @State private var actionError: String?

    enum DetailTab: String, CaseIterable, Identifiable {
        case workflow = "Workflow"
        case graph = "Graph"
        case script = "Script"
        case prompts = "Prompts"
        case voiceover = "Voiceover"
        case clips = "Clips"
        case log = "Log"

        var id: String { rawValue }
    }

    private var clips: [ClipRecord] { project.loadClips() }
    private var videoStatus: (done: Int, total: Int) { project.videoStatus(for: clips) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("Tab", selection: $tab) {
                ForEach(DetailTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch tab {
                case .workflow:
                    WorkflowView(project: project, actionError: $actionError)
                case .graph:
                    WorkflowGraphView(project: project)
                case .script:
                    ScriptReviewView(script: project.loadScript())
                case .prompts:
                    PromptsView(decisions: project.loadDecisions(), clips: clips)
                case .voiceover:
                    VoiceoverView(project: project)
                case .clips:
                    ClipsGalleryView(
                        project: project,
                        clips: clips,
                        selectedClipID: $selectedClipID
                    )
                case .log:
                    LogView(log: store.pipeline.logText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(project.manifest.title)
        .onAppear {
            if selectedClipID == nil { selectedClipID = clips.first?.id }
            store.refreshProjects()
        }
        .onChange(of: project.id) { _, _ in
            selectedClipID = project.loadClips().first?.id
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                PhaseBadge(phase: project.manifest.phase)
                if let url = URL(string: project.manifest.blogURL) {
                    Link(project.manifest.blogURL, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    if !clips.isEmpty {
                        Text("\(videoStatus.done)/\(videoStatus.total) clips")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if project.hasVoiceover {
                        Label("Voiceover", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                store.revealInFinder(project)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        .padding()
    }
}

struct WorkflowView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject
    @Binding var actionError: String?

    @State private var isWorking = false

    private var current: VideoProject {
        store.selectedProject ?? project
    }

    private var clips: [ClipRecord] { current.loadClips() }
    private var videoStatus: (done: Int, total: Int) { current.videoStatus(for: clips) }
    private var videosComplete: Bool {
        videoStatus.total > 0 && videoStatus.done >= videoStatus.total
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Run any step at any time. Steps only need their inputs — you can generate voiceover after clips, or re-run a step.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let err = current.manifest.lastError ?? actionError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                stepCard(
                    number: 1,
                    title: "Script",
                    subtitle: "From blog URL (created at project start)",
                    done: current.hasScript,
                    active: store.pipeline.runningStep == .generateScript
                ) {
                    if current.hasScript {
                        Text("Ready — see Script tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                stepCard(
                    number: 2,
                    title: "Clip prompts",
                    subtitle: "Decisions + Veo prompts (no video cost)",
                    done: current.hasClipsJSON,
                    active: store.pipeline.runningStep == .generatePrompts
                ) {
                    runButton(
                        title: current.hasClipsJSON ? "Regenerate clip prompts" : "Generate clip prompts",
                        enabled: current.hasScript
                    ) {
                        Task { await run(.generatePrompts) }
                    }
                }

                stepCard(
                    number: 3,
                    title: "Voiceover",
                    subtitle: "Gemini TTS timed to clip lengths",
                    done: current.hasVoiceover,
                    active: store.pipeline.runningStep == .generateVoiceover
                ) {
                    runButton(
                        title: current.hasVoiceover ? "Regenerate voiceover" : "Generate voiceover",
                        enabled: current.hasClipsJSON
                    ) {
                        Task { await run(.generateVoiceover) }
                    }
                    if current.hasVoiceover {
                        Text("Listen in Voiceover tab")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                stepCard(
                    number: 4,
                    title: "Video clips",
                    subtitle: videoStatusLabel,
                    done: videosComplete,
                    active: store.pipeline.runningStep == .generateVideos
                        || isRegeneratingAnyClip
                ) {
                    runButton(
                        title: videoButtonTitle,
                        enabled: current.hasClipsJSON
                    ) {
                        Task { await run(.generateVideos) }
                    }
                    if videoStatus.done > 0 {
                        Text("\(videoStatus.done)/\(videoStatus.total) clips in project folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.pipeline.isRunning || isWorking {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView()
                        LogView(log: store.pipeline.logText)
                            .frame(minHeight: 120)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var videoStatusLabel: String {
        if videosComplete { return "All clips generated" }
        if videoStatus.done > 0 { return "Partial — resume to finish (paid)" }
        return "Veo generation (paid)"
    }

    private var videoButtonTitle: String {
        if videosComplete { return "Regenerate missing clips" }
        if videoStatus.done > 0 { return "Resume video generation" }
        return "Generate videos"
    }

    @ViewBuilder
    private func runButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .disabled(!enabled || isWorking || store.pipeline.isRunning)
    }

    @ViewBuilder
    private func stepCard<Actions: View>(
        number: Int,
        title: String,
        subtitle: String,
        done: Bool,
        active: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                    .frame(width: 36, height: 36)
                if active {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if done {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.headline)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                actions()
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func run(_ step: PipelineService.PipelineStep) async {
        actionError = nil
        isWorking = true
        defer { isWorking = false }
        let p = store.selectedProject ?? project
        do {
            try await store.runWorkflowStep(p, step: step)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var isRegeneratingAnyClip: Bool {
        if case .regenerateClip = store.pipeline.runningStep { return true }
        return false
    }
}
