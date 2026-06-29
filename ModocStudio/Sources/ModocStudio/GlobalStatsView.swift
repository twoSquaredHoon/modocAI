import SwiftUI

struct GlobalProjectStatsRow: Identifiable {
    let id: String
    let project: VideoProject
    let summary: PipelineLanguageSummary
    let batchFolder: String?
}

private enum ArticleReviewFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case passed = "Passed"
    case failed = "Failed"
    case unreviewed = "Unreviewed"

    var id: String { rawValue }
}

struct GlobalStatsView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var selectedLanguage: ProjectLanguage?
    @State private var reviewFilter: ArticleReviewFilter = .all
    @State private var timingRows: [GlobalProjectStatsRow] = []
    @State private var refreshTimer: Timer?

    private var completedByLanguage: [(language: ProjectLanguage, projects: [VideoProject])] {
        store.completedProjectsGroupedByLanguage()
    }

    private var languageTotals: [(language: ProjectLanguage, automated: Double, review: Double, total: Double, projectCount: Int)] {
        store.languageTimingTotals()
    }

    private var grandTotals: (automated: Double, review: Double, pipeline: Double) {
        languageTotals.reduce(into: (0.0, 0.0, 0.0)) { acc, row in
            acc.0 += row.automated
            acc.1 += row.review
            acc.2 += row.total
        }
    }

    private var activeLanguage: ProjectLanguage? {
        if let selectedLanguage,
           completedByLanguage.contains(where: { $0.language == selectedLanguage }) {
            return selectedLanguage
        }
        return completedByLanguage.first?.language
    }

    private var activeCompletedProjects: [VideoProject] {
        guard let lang = activeLanguage else { return [] }
        return completedByLanguage.first { $0.language == lang }?.projects ?? []
    }

    private var filteredCompletedProjects: [VideoProject] {
        switch reviewFilter {
        case .all:
            return activeCompletedProjects
        case .passed:
            return activeCompletedProjects.filter { $0.manifest.articleReviewStatus == .passed }
        case .failed:
            return activeCompletedProjects.filter { $0.manifest.articleReviewStatus == .failed }
        case .unreviewed:
            return activeCompletedProjects.filter { $0.manifest.articleReviewStatus == nil }
        }
    }

    private func reviewCount(for filter: ArticleReviewFilter) -> Int {
        switch filter {
        case .all:
            return activeCompletedProjects.count
        case .passed:
            return activeCompletedProjects.filter { $0.manifest.articleReviewStatus == .passed }.count
        case .failed:
            return activeCompletedProjects.filter { $0.manifest.articleReviewStatus == .failed }.count
        case .unreviewed:
            return activeCompletedProjects.filter { $0.manifest.articleReviewStatus == nil }.count
        }
    }

    var body: some View {
        Group {
            switch store.statsSubsection {
            case .hub:
                statsHub
            case .projects:
                projectsScreen
            case .time:
                timeScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { reload() }
        .onDisappear { refreshTimer?.invalidate() }
        .onChange(of: store.statsRefreshToken) { _, _ in reload() }
        .onChange(of: store.statsSubsection) { _, section in
            if section == .projects, selectedLanguage == nil {
                selectedLanguage = completedByLanguage.first?.language
            }
        }
    }

    // MARK: - Hub

    private var statsHub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stats")
                        .font(.largeTitle.bold())
                    Text("Choose completed articles or pipeline timing.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 20) {
                    hubCard(
                        title: "Completed Articles",
                        subtitle: "Finished videos by language — article titles and blog links.",
                        systemImage: "checkmark.circle.fill",
                        tint: .blue
                    ) {
                        selectedLanguage = completedByLanguage.first?.language
                        store.statsSubsection = .projects
                    }

                    hubCard(
                        title: "Pipeline Time",
                        subtitle: "Automated runs and manual review time across projects.",
                        systemImage: "chart.bar.fill",
                        tint: .green
                    ) {
                        store.statsSubsection = .time
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private func hubCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Open")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Projects

    private var projectsScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Completed Articles")
                        .font(.largeTitle.bold())
                    Text("One language at a time — titles and source links for finished videos.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if completedByLanguage.isEmpty {
                    ContentUnavailableView(
                        "No completed articles yet",
                        systemImage: "checkmark.circle",
                        description: Text("Finished videos (Ready) will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    filterControlsRow

                    if let lang = activeLanguage {
                        HStack(spacing: 8) {
                            LanguageBadge(language: lang)
                            Text(lang.displayName)
                                .font(.headline)
                            Text("\(filteredCompletedProjects.count) shown")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }

                        if filteredCompletedProjects.isEmpty {
                            Text(emptyFilterMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(filteredCompletedProjects) { project in
                                    StatsCompletedArticleRow(project: project)
                                }
                            }
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var languageSelection: Binding<ProjectLanguage> {
        Binding(
            get: { activeLanguage ?? completedByLanguage.first?.language ?? .en },
            set: { selectedLanguage = $0 }
        )
    }

    private var filterControlsRow: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Language")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Language", selection: languageSelection) {
                    ForEach(completedByLanguage, id: \.language) { group in
                        Text("\(group.language.displayName) (\(group.projects.count))")
                            .tag(group.language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Review status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Review status", selection: $reviewFilter) {
                    ForEach(ArticleReviewFilter.allCases) { filter in
                        Text("\(filter.rawValue) (\(reviewCount(for: filter)))")
                            .tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 160, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyFilterMessage: String {
        switch reviewFilter {
        case .all:
            return "No completed articles for this language."
        case .passed:
            return "No passed articles for this filter."
        case .failed:
            return "No failed articles for this filter."
        case .unreviewed:
            return "All articles in this language have been reviewed."
        }
    }

    // MARK: - Time

    private var timeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pipeline Time")
                        .font(.largeTitle.bold())
                    Text("Automated pipeline runs and manual review time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                timeContent
            }
            .padding(32)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    @ViewBuilder
    private var timeContent: some View {
        if timingRows.isEmpty && languageTotals.isEmpty {
            ContentUnavailableView(
                "No timing data yet",
                systemImage: "chart.bar",
                description: Text("Run pipeline steps on projects to collect timing.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                grandTotalsCard

                if !languageTotals.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("By language")
                            .font(.headline)
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(languageTotals, id: \.language) { row in
                                languageTimingCard(row)
                            }
                        }
                    }
                }

                if !timingRows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("By project")
                            .font(.headline)
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(timingRows) { row in
                                projectTimingCard(row)
                            }
                        }
                    }
                }
            }
        }
    }

    private var grandTotalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All languages")
                .font(.subheadline.weight(.semibold))
            statRow("Total automated", PipelineDurationFormat.string(seconds: grandTotals.automated))
            statRow("Total manual review", PipelineDurationFormat.string(seconds: grandTotals.review))
            Divider()
            statRow("Combined pipeline time", PipelineDurationFormat.string(seconds: grandTotals.pipeline))
                .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func languageTimingCard(
        _ row: (language: ProjectLanguage, automated: Double, review: Double, total: Double, projectCount: Int)
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LanguageBadge(language: row.language)
                Text(row.language.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            Text("\(row.projectCount) timed project\(row.projectCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            statRow("Automated", PipelineDurationFormat.string(seconds: row.automated))
            statRow("Review", PipelineDurationFormat.string(seconds: row.review))
            statRow("Total", PipelineDurationFormat.string(seconds: row.total))
                .font(.caption.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func projectTimingCard(_ row: GlobalProjectStatsRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.project.manifest.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 6) {
                LanguageBadge(language: row.project.manifest.language)
                PhaseBadge(phase: row.project.manifest.phase)
            }
            if let batch = row.batchFolder {
                Text(batch)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                timingPill("Auto", row.summary.totalAutomatedSeconds)
                timingPill("Review", row.summary.totalReviewSeconds)
                timingPill("Total", row.summary.totalPipelineSeconds, emphasized: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func timingPill(_ label: String, _ seconds: Double, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(PipelineDurationFormat.string(seconds: seconds))
                .font(emphasized ? .caption.weight(.semibold).monospacedDigit() : .caption.monospacedDigit())
        }
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
        timingRows = store.globalStatsRows()
        if selectedLanguage == nil {
            selectedLanguage = completedByLanguage.first?.language
        }
        store.scheduleRefreshProjects(autoSelect: false)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                timingRows = store.globalStatsRows()
            }
        }
    }
}

private struct StatsCompletedArticleRow: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    @State private var isHovered = false
    @State private var notesText = ""

    private var current: VideoProject {
        store.projects.first { $0.id == project.id } ?? project
    }

    private var reviewStatus: ArticleReviewStatus? {
        current.manifest.articleReviewStatus
    }

    private var cardFill: Color {
        switch reviewStatus {
        case .passed:
            return Color.green.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        case nil:
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var cardStroke: Color {
        switch reviewStatus {
        case .passed:
            return Color.green.opacity(0.4)
        case .failed:
            return Color.red.opacity(0.4)
        case nil:
            return Color.primary.opacity(0.08)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(current.manifest.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, isHovered ? 56 : 0)

            if let url = URL(string: current.manifest.blogURL) {
                Link(destination: url) {
                    Text(current.manifest.blogURL)
                        .font(.caption)
                        .foregroundStyle(.link)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.trailing, isHovered ? 56 : 0)
            } else {
                Text(current.manifest.blogURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, isHovered ? 56 : 0)
            }

            if reviewStatus == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $notesText)
                        .font(.caption)
                        .frame(minHeight: 56, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .onChange(of: notesText) { _, newValue in
                            store.setArticleReviewNotes(current, notes: newValue)
                        }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardStroke, lineWidth: reviewStatus == nil ? 1 : 1.5)
        )
        .overlay(alignment: .trailing) {
            if isHovered {
                HStack(spacing: 4) {
                    reviewActionButton(
                        systemImage: "checkmark.square",
                        tint: .green,
                        isActive: reviewStatus == .passed,
                        help: reviewStatus == .passed ? "Clear pass" : "Mark as passed"
                    ) {
                        if reviewStatus == .passed {
                            store.clearArticleReviewStatus(current)
                        } else {
                            store.setArticleReviewStatus(current, status: .passed)
                        }
                    }

                    reviewActionButton(
                        systemImage: "xmark.square",
                        tint: .red,
                        isActive: reviewStatus == .failed,
                        help: reviewStatus == .failed ? "Clear fail" : "Mark as failed"
                    ) {
                        if reviewStatus == .failed {
                            store.clearArticleReviewStatus(current)
                            notesText = ""
                        } else {
                            store.setArticleReviewStatus(current, status: .failed)
                            notesText = current.manifest.articleReviewNotes ?? ""
                        }
                    }
                }
                .padding(10)
                .transition(.opacity)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onAppear {
            notesText = current.manifest.articleReviewNotes ?? ""
        }
        .onChange(of: current.manifest.articleReviewNotes) { _, newValue in
            if notesText != (newValue ?? "") {
                notesText = newValue ?? ""
            }
        }
    }

    private func reviewActionButton(
        systemImage: String,
        tint: Color,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(isActive ? tint : tint.opacity(0.75))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? tint.opacity(0.18) : Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? tint.opacity(0.6) : Color.primary.opacity(0.15), lineWidth: isActive ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
