import SwiftUI

struct GlobalProjectStatsRow: Identifiable {
    let id: String
    let project: VideoProject
    let summary: PipelineLanguageSummary
    let batchFolder: String?
}

struct GlobalStatsView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var rows: [GlobalProjectStatsRow] = []
    @State private var refreshTimer: Timer?

    private var totals: (automated: Double, review: Double, pipeline: Double) {
        rows.reduce(into: (0.0, 0.0, 0.0)) { acc, row in
            acc.0 += row.summary.totalAutomatedSeconds
            acc.1 += row.summary.totalReviewSeconds
            acc.2 += row.summary.totalPipelineSeconds
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                ContentUnavailableView(
                    "No timing data yet",
                    systemImage: "chart.bar",
                    description: Text("Run pipeline steps on projects to collect automated and review time.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        totalsCard
                        projectTable
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .withHomeToolbar(title: "Stats")
        .onAppear { reload() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pipeline statistics")
                .font(.headline)
            Text("Aggregated across \(rows.count) project(s) with timing data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All projects")
                .font(.subheadline.weight(.semibold))
            statRow("Total automated", PipelineDurationFormat.string(seconds: totals.automated))
            statRow("Total manual review", PipelineDurationFormat.string(seconds: totals.review))
            Divider()
            statRow("Combined pipeline time", PipelineDurationFormat.string(seconds: totals.pipeline))
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var projectTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By project")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    headerCell("Project")
                    headerCell("Lang")
                    headerCell("Phase")
                    headerCell("Automated")
                    headerCell("Review")
                    headerCell("Total")
                }
                Divider().gridCellColumns(6)
                ForEach(rows) { row in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.project.manifest.title)
                                .lineLimit(2)
                            if let batch = row.batchFolder {
                                Text(batch)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        LanguageBadge(language: row.project.manifest.language)
                        PhaseBadge(phase: row.project.manifest.phase)
                        Text(PipelineDurationFormat.string(seconds: row.summary.totalAutomatedSeconds))
                            .font(.caption.monospacedDigit())
                        Text(PipelineDurationFormat.string(seconds: row.summary.totalReviewSeconds))
                            .font(.caption.monospacedDigit())
                        Text(PipelineDurationFormat.string(seconds: row.summary.totalPipelineSeconds))
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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

    private func reload() {
        store.refreshProjects()
        rows = store.globalStatsRows()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                rows = store.globalStatsRows()
            }
        }
    }
}
