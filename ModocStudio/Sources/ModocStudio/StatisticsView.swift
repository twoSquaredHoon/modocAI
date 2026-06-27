import SwiftUI

struct StatisticsView: View {
    let project: VideoProject

    @State private var statsFile: PipelineStatsFile = .empty()
    @State private var refreshTimer: Timer?

    private var projectLanguage: ProjectLanguage { project.manifest.language }

    private var summary: PipelineLanguageSummary? {
        PipelineTimeTracker.summaries(for: project).first { $0.language == projectLanguage }
    }

    var body: some View {
        Group {
            if statsFile.projectStartedAt == nil && summary?.stats.startedAt == nil {
                ContentUnavailableView(
                    "No timing data yet",
                    systemImage: "chart.bar",
                    description: Text("Run workflow steps to start recording pipeline time for this project.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let summary {
                                overviewCard(summary)
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
            HStack(spacing: 8) {
                Text("Pipeline statistics")
                    .font(.headline)
                LanguageBadge(language: projectLanguage)
            }
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

    private func overviewCard(_ summary: PipelineLanguageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.language.displayName)
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func languageDetail(_ summary: PipelineLanguageSummary) -> some View {
        let stats = summary.stats

        Group {
            if let started = stats.startedAt {
                Text("Work started: \(formatISO(started))")
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
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                statsFile = PipelineTimeTracker.load(for: project)
            }
        }
    }
}
