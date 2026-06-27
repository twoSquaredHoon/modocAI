import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    @State private var tab: DetailTab = .workflow
    @State private var selectedClipID: String?
    @State private var actionError: String?
    @State private var confirmDeleteProject = false

    enum DetailTab: String, CaseIterable, Identifiable {
        case workflow = "Workflow"
        case script = "Script"
        case articleCheck = "Article check"
        case prompts = "Prompts"
        case voiceover = "Voiceover"
        case clips = "Clips"
        case log = "Log"
        case statistics = "Statistics"
        case graph = "Graph"

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
                    WorkflowView(project: current, actionError: $actionError, selectedTab: $tab)
                case .graph:
                    WorkflowGraphView(project: current)
                case .statistics:
                    StatisticsView(project: current)
                case .script:
                    ScriptReviewView(
                        project: current,
                        script: current.loadScript(),
                        clips: clips
                    )
                case .articleCheck:
                    ScriptCheckView(project: current)
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
        .confirmationDialog(
            "Delete “\(current.manifest.title)”?",
            isPresented: $confirmDeleteProject,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                deleteCurrentProject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project folder and all scripts, clips, and videos will be moved to the Trash.")
        }
    }

    private func deleteCurrentProject() {
        do {
            try store.deleteProject(current)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PhaseBadge(phase: current.manifest.phase)
                    LanguageBadge(language: current.manifest.language)
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
            Button(role: .destructive) {
                confirmDeleteProject = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(store.pipeline.isRunning)
        }
        .padding()
    }
}

struct LanguageBadge: View {
    let language: ProjectLanguage

    var body: some View {
        Text(language.shortLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
            .help(language.displayName)
    }
}

struct WorkflowView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject
    @Binding var actionError: String?
    @Binding var selectedTab: ProjectDetailView.DetailTab

    @State private var isWorking = false
    @State private var confirmFinalize = false
    @State private var autoIncludeVideos = true
    @State private var confirmAutoPipeline = false

    private var pendingAutoSteps: [PipelineService.PipelineStep] {
        AutoPipelineOptions.full(includeVideos: autoIncludeVideos).pendingSteps(for: current)
    }
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

                autoPipelineSection

                stepCard(
                    number: 1,
                    title: "Script",
                    subtitle: "From blog URL · \(current.manifest.language.displayName)",
                    done: languageHasWork && current.hasScript,
                    active: store.pipeline.runningStep == .generateScript
                        || store.pipeline.runningStep == .verifyScript
                ) {
                    runButton(
                        title: current.hasScript ? "Regenerate script" : "Generate script",
                        enabled: !current.manifest.blogURL.isEmpty
                    ) {
                        Task { await run(.generateScript) }
                    }
                    if current.hasScript {
                        Text("Review in Script tab · fact-check in Article check tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if current.hasScriptVerification, let v = current.loadScriptVerification() {
                        Button {
                            selectedTab = .articleCheck
                        } label: {
                            Label("Article check: \(v.verdict.label)", systemImage: v.verdict.icon)
                                .font(.caption)
                                .foregroundStyle(v.verdict.color)
                        }
                        .buttonStyle(.plain)
                    }
                    runButton(
                        title: "Compare script to article",
                        enabled: !current.manifest.blogURL.isEmpty && current.hasScript
                    ) {
                        Task { await run(.verifyScript, thenOpenArticleCheck: true) }
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

    private var autoPipelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Auto pipeline")
                .font(.headline)
            Text("Run every remaining step in workflow order. Already-complete steps are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if pendingAutoSteps.isEmpty {
                Label("All steps complete — review clips and voiceover, then remake anything you want.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Text("Will run: \(pendingAutoSteps.map(\.title).joined(separator: " → "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Include Veo videos (paid API)", isOn: $autoIncludeVideos)
                    .font(.caption)
                    .disabled(store.pipeline.isRunning || isWorking)

                Button {
                    confirmAutoPipeline = true
                } label: {
                    Label("Run remaining steps", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.pipeline.isRunning || isWorking)
                .confirmationDialog(
                    "Run \(pendingAutoSteps.count) remaining pipeline step(s)?",
                    isPresented: $confirmAutoPipeline,
                    titleVisibility: .visible
                ) {
                    Button("Run pipeline") {
                        Task { await runAutoPipeline() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(pendingAutoSteps.map(\.title).joined(separator: " → "))
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
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

    private func runAutoPipeline() async {
        actionError = nil
        isWorking = true
        defer { isWorking = false }
        let p = store.selectedProject ?? project
        do {
            try await store.runAutoPipeline(
                p,
                options: .full(includeVideos: autoIncludeVideos)
            )
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func run(_ step: PipelineService.PipelineStep, thenOpenArticleCheck: Bool = false) async {
        actionError = nil
        isWorking = true
        defer { isWorking = false }
        let p = store.selectedProject ?? project
        do {
            try await store.runWorkflowStep(p, step: step)
            if thenOpenArticleCheck {
                selectedTab = .articleCheck
            }
        } catch {
            actionError = error.localizedDescription
            if thenOpenArticleCheck {
                selectedTab = .articleCheck
            }
        }
    }

    private var isRegeneratingAnyClip: Bool {
        if case .regenerateClip = store.pipeline.runningStep { return true }
        if store.pipeline.runningStep == .regenerateAllClips { return true }
        return false
    }
}
