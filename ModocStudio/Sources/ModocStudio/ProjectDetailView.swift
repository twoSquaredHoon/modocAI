import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    @State private var tab: DetailTab = .workflow
    @State private var selectedClipID: String?
    @State private var actionError: String?
    @State private var showLanguageHint = false

    enum DetailTab: String, CaseIterable, Identifiable {
        case workflow = "Workflow"
        case graph = "Graph"
        case statistics = "Statistics"
        case script = "Script"
        case prompts = "Prompts"
        case voiceover = "Voiceover"
        case clips = "Clips"
        case log = "Log"

        var id: String { rawValue }
    }

    private var clips: [ClipRecord] { current.loadClips() }
    private var videoStatus: (done: Int, total: Int) { current.videoStatus(for: clips) }

    private var current: VideoProject {
        store.selectedProject ?? project
    }

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
                    WorkflowView(project: current, actionError: $actionError)
                case .graph:
                    WorkflowGraphView(project: current)
                case .statistics:
                    StatisticsView(project: current)
                case .script:
                    ScriptReviewView(script: current.loadScript())
                case .prompts:
                    PromptsView(decisions: current.loadDecisions(), clips: clips)
                case .voiceover:
                    VoiceoverView(project: current)
                case .clips:
                    ClipsGalleryView(
                        project: current,
                        clips: clips,
                        selectedClipID: $selectedClipID
                    )
                case .log:
                    LogView(log: store.pipeline.logText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(current.manifest.title)
        .onAppear {
            if selectedClipID == nil { selectedClipID = clips.first?.id }
            store.refreshProjects()
        }
        .onChange(of: project.id) { _, _ in
            selectedClipID = current.loadClips().first?.id
        }
        .onChange(of: current.manifest.language) { _, _ in
            selectedClipID = current.loadClips().first?.id
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PhaseBadge(phase: current.manifest.phase)
                    languagePicker
                }
                if showLanguageHint {
                    Text("\(current.manifest.language.shortLabel) has no saved work yet — workflow starts fresh. Run Script to begin.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let url = URL(string: current.manifest.blogURL) {
                    Link(current.manifest.blogURL, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    if !clips.isEmpty {
                        Text("\(videoStatus.done)/\(videoStatus.total) clips")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if current.hasVoiceover {
                        Label("Voiceover", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                store.revealInFinder(current)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        .padding()
    }

    private var languagePicker: some View {
        Picker("Language", selection: languageBinding) {
            ForEach(ProjectLanguage.allCases, id: \.self) { lang in
                Text(lang.shortLabel).tag(lang)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 140)
        .disabled(store.pipeline.isRunning)
    }

    private var languageBinding: Binding<ProjectLanguage> {
        Binding(
            get: { current.manifest.language },
            set: { newLanguage in
                let previous = current.manifest.language
                store.setProjectLanguage(current, language: newLanguage)
                showLanguageHint = previous != newLanguage && !current.hasAnyWork(for: newLanguage)
            }
        )
    }
}

struct WorkflowView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject
    @Binding var actionError: String?

    @State private var isWorking = false
    @State private var confirmFinalize = false

    private var current: VideoProject {
        store.selectedProject ?? project
    }

    private var activeLanguage: ProjectLanguage { current.manifest.language }
    private var isFinalized: Bool { store.isLanguageFinalized(current, language: activeLanguage) }
    private var pipelineSummary: PipelineLanguageSummary? {
        PipelineTimeTracker.summaries(for: current).first { $0.language == activeLanguage }
    }

    private var clips: [ClipRecord] { current.loadClips() }
    private var videoStatus: (done: Int, total: Int) { current.videoStatus(for: clips) }
    private var languageHasWork: Bool { current.hasAnyWork(for: current.manifest.language) }
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
                    subtitle: "From blog URL · follows EN / KO / ES setting",
                    done: languageHasWork && current.hasScript,
                    active: store.pipeline.runningStep == .generateScript
                ) {
                    runButton(
                        title: current.hasScript ? "Regenerate script" : "Generate script",
                        enabled: !current.manifest.blogURL.isEmpty
                    ) {
                        Task { await run(.generateScript) }
                    }
                    if current.hasScript {
                        Text("Review in Script tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                stepCard(
                    number: 2,
                    title: "Clip prompts",
                    subtitle: "Decisions + Veo prompts with consistent cast (matches EN/KO/ES)",
                    done: languageHasWork && current.hasClipsJSON,
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
                    done: languageHasWork && current.hasVoiceover,
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
                    done: languageHasWork && videosComplete,
                    active: store.pipeline.runningStep == .generateVideos
                        || isRegeneratingAnyClip
                        || store.pipeline.runningStep == .regenerateAllClips
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

                finalizeSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var finalizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Pipeline timing")
                .font(.headline)
            Text("Finalize when you are done reviewing this language version. Manual review time stops and totals appear in Statistics.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let summary = pipelineSummary, summary.stats.startedAt != nil {
                HStack(spacing: 16) {
                    timingChip("Automated", summary.totalAutomatedSeconds)
                    timingChip("Review", summary.totalReviewSeconds)
                    timingChip("Total", summary.totalPipelineSeconds)
                }
            }

            HStack(spacing: 12) {
                if isFinalized {
                    Label("Finalized for \(activeLanguage.shortLabel)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }

                Button {
                    confirmFinalize = true
                } label: {
                    Label(
                        isFinalized ? "Re-finalize \(activeLanguage.shortLabel)" : "Finalize \(activeLanguage.shortLabel)",
                        systemImage: "checkmark.seal"
                    )
                }
                .disabled(store.pipeline.isRunning || isWorking)
                .confirmationDialog(
                    "Finalize pipeline for \(activeLanguage.shortLabel)?",
                    isPresented: $confirmFinalize,
                    titleVisibility: .visible
                ) {
                    Button("Finalize & stop review timer") {
                        store.finalizePipelineLanguage(current, language: activeLanguage)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Closes any open manual review period and marks this language lane complete for KPI tracking. Running another step will reopen tracking.")
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func timingChip(_ label: String, _ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(PipelineDurationFormat.string(seconds: seconds))
                .font(.caption.monospacedDigit().weight(.medium))
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
        if store.pipeline.runningStep == .regenerateAllClips { return true }
        return false
    }
}
