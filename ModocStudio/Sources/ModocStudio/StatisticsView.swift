import SwiftUI

struct StatisticsView: View {
    let project: VideoProject

    @State private var statsFile: PipelineStatsFile = .empty()
    @State private var refreshTimer: Timer?
    @State private var selectedLanguage: ProjectLanguage = .en

    private var summaries: [PipelineLanguageSummary] {
        PipelineTimeTracker.summaries(for: project)
    }

    private var selectedSummary: PipelineLanguageSummary? {
        summaries.first { $0.language == selectedLanguage }
    }

    var body: some View {
        Group {
            if statsFile.projectStartedAt == nil && summaries.allSatisfy({ $0.stats.startedAt == nil }) {
                ContentUnavailableView(
                    "No timing data yet",
                    systemImage: "chart.bar",
                    description: Text("Run workflow steps or switch languages to start recording pipeline time.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            overviewCards
                            languagePicker
                            if let summary = selectedSummary {
                                languageDetail(summary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { reload() }
        .onDisappear { refreshTimer?.invalidate() }
        .onChange(of: project.id) { _, _ in reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pipeline statistics")
                .font(.headline)
            Text("Automated time = AI/pipeline runs. Manual review = your time between steps until the next run or Finalize.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let started = statsFile.projectStartedAt {
                Text("Project started: \(formatISO(started))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    private var overviewCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(summaries) { summary in
                overviewCard(summary)
            }
        }
    }

    private func overviewCard(_ summary: PipelineLanguageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.language.shortLabel)
                    .font(.headline)
                Spacer()
                if summary.isFinalized {
                    Text("Finalized")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                } else if summary.hasOpenReview {
                    Text("Reviewing")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            statRow("Automated", PipelineDurationFormat.string(seconds: summary.totalAutomatedSeconds))
            statRow("Manual review", PipelineDurationFormat.string(seconds: summary.totalReviewSeconds))
            Divider()
            statRow("Total pipeline", PipelineDurationFormat.string(seconds: summary.totalPipelineSeconds))
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(summary.language == selectedLanguage
                    ? Color.accentColor.opacity(0.08)
                    : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(summary.language == selectedLanguage ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { selectedLanguage = summary.language }
    }

    private var languagePicker: some View {
        Picker("Language detail", selection: $selectedLanguage) {
            ForEach(ProjectLanguage.allCases, id: \.self) { lang in
                Text(lang.displayName).tag(lang)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func languageDetail(_ summary: PipelineLanguageSummary) -> some View {
        let stats = summary.stats

        Group {
            if let started = stats.startedAt {
                Text("Language work started: \(formatISO(started))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let finalized = stats.finalizedAt {
                Text("Finalized: \(formatISO(finalized))")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if summary.hasOpenReview,
               let after = stats.openReviewAfterStepLabel,
               stats.openReviewStartedAt != nil {
                Label(
                    "Review in progress after \(after) · \(PipelineDurationFormat.string(seconds: summary.openReviewSeconds)) so far",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.vertical, 4)
            }
        }

        if !stats.automatedRuns.isEmpty {
            sectionTitle("Automated runs")
            ForEach(stats.automatedRuns) { run in
                runRow(run)
            }
        }

        if !stats.manualReviews.isEmpty {
            sectionTitle("Manual review periods")
            ForEach(stats.manualReviews) { review in
                reviewRow(review)
            }
        }

        if !stats.languageSwitches.isEmpty {
            sectionTitle("Language switches (from this lane)")
            ForEach(Array(stats.languageSwitches.enumerated()), id: \.offset) { _, sw in
                Text("→ \(sw.toLanguage.uppercased()) at \(formatISO(sw.at))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.top, 8)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func runRow(_ run: PipelineAutomatedRun) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.label)
                    .font(.subheadline.weight(.medium))
                Text(formatISO(run.startedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(PipelineDurationFormat.string(seconds: run.durationSeconds))
                    .font(.subheadline.monospacedDigit())
                Text(run.success ? "success" : "failed")
                    .font(.caption2)
                    .foregroundStyle(run.success ? .green : .red)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func reviewRow(_ review: PipelineManualReview) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("After \(review.afterStepLabel)")
                    .font(.subheadline.weight(.medium))
                Text("Ended by: \(review.endedBy.replacingOccurrences(of: "_", with: " "))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(PipelineDurationFormat.string(seconds: review.durationSeconds))
                .font(.subheadline.monospacedDigit())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func formatISO(_ iso: String) -> String {
        guard let date = PipelineDurationFormat.parse(iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private func reload() {
        statsFile = PipelineTimeTracker.load(for: project)
        selectedLanguage = project.manifest.language
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                statsFile = PipelineTimeTracker.load(for: project)
            }
        }
    }
}
