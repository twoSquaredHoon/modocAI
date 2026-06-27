import SwiftUI

struct ScriptCheckView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject

    @State private var liveScript: String = ""
    @State private var report: ScriptVerificationReport?
    @State private var disregardedLineIDs: Set<String> = []
    @State private var isVerifying = false
    @State private var isEditingLine = false
    @State private var actionError: String?
    @State private var statusMessage: String?
    @State private var selectedLineID: String?
    @State private var showIssuesOnly = false
    @State private var confirmDismissLineID: String?
    @State private var refreshID = UUID()

    private var lines: [ScriptLine] { ScriptParser.parse(liveScript) }

    private var current: VideoProject {
        store.selectedProject ?? project
    }

    private var annotatedLines: [AnnotatedScriptLine] {
        guard let report else {
            return lines.map { AnnotatedScriptLine(line: $0, check: nil, linkedIssues: []) }
        }
        return report.annotate(lines: lines, disregarded: disregardedLineIDs)
    }

    private var visibleLines: [AnnotatedScriptLine] {
        if showIssuesOnly {
            return annotatedLines.filter(\.hasActiveIssue)
        }
        return annotatedLines
    }

    private var activeIssueCount: Int {
        guard let report else { return 0 }
        return report.activeIssueLineCount(in: lines, disregarded: disregardedLineIDs)
    }

    private var selectedAnnotation: AnnotatedScriptLine? {
        guard let selectedLineID else { return nil }
        return annotatedLines.first { $0.id == selectedLineID }
    }

    private var isBusy: Bool {
        isVerifying || isEditingLine || store.pipeline.isRunning
    }

    var body: some View {
        VStack(spacing: 0) {
            if liveScript.isEmpty {
                ContentUnavailableView(
                    "No script yet",
                    systemImage: "doc.text",
                    description: Text("Generate a script first, then compare it to the blog article.")
                )
            } else if current.manifest.blogURL.isEmpty {
                ContentUnavailableView(
                    "No blog URL",
                    systemImage: "link.badge.plus",
                    description: Text("This project needs a blog URL to fetch the original article.")
                )
            } else {
                toolbar
                if let statusMessage {
                    statusBanner(statusMessage)
                }
                Divider()

                if isVerifying || store.pipeline.runningStep == .verifyScript {
                    runningState("Gemini is comparing each script line to the original article…")
                } else if isEditingLine || isRewritingLine {
                    runningState("Gemini is rewriting the selected line…")
                } else if let actionError, report == nil {
                    errorState(actionError)
                } else if let report {
                    reportContent(report)
                } else {
                    emptyState
                }
            }
        }
        .id(refreshID)
        .onAppear { reloadAll() }
        .onChange(of: current.id) { _, _ in reloadAll() }
        .confirmationDialog(
            "Remove this line from the script?",
            isPresented: Binding(
                get: { confirmDismissLineID != nil },
                set: { if !$0 { confirmDismissLineID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove line", role: .destructive) {
                if let lineID = confirmDismissLineID {
                    Task { await dismissLine(lineID) }
                }
                confirmDismissLineID = nil
            }
            Button("Cancel", role: .cancel) { confirmDismissLineID = nil }
        } message: {
            if let lineID = confirmDismissLineID,
               let text = lines.first(where: { $0.id == lineID })?.text {
                Text("“\(text)” will be deleted from script.txt. Re-run the article check afterward.")
            }
        }
    }

    private var isRewritingLine: Bool {
        if case .rewriteScriptLine = store.pipeline.runningStep { return true }
        return false
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if let report {
                Label(report.verdict.label, systemImage: report.verdict.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(report.verdict.color)

                if report.issueLineCount > 0 || !disregardedLineIDs.isEmpty {
                    if activeIssueCount > 0 {
                        Text("\(activeIssueCount) open issue(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !disregardedLineIDs.isEmpty {
                        Text("\(disregardedLineIDs.count) disregarded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if report != nil {
                Toggle("Issues only", isOn: $showIssuesOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            if isBusy {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await runVerification() }
            } label: {
                Label(report == nil ? "Compare with article" : "Re-run check", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(isBusy)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Dismiss") { statusMessage = nil }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.08))
    }

    private func runningState(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
            LogView(log: store.pipeline.logText)
                .frame(maxHeight: 240)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Article check failed", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text(message)
                    .font(.body)
                    .textSelection(.enabled)

                if !store.pipeline.logText.isEmpty {
                    Text("Log")
                        .font(.subheadline.weight(.semibold))
                    LogView(log: store.pipeline.logText)
                        .frame(minHeight: 160)
                }

                Button("Try again") {
                    Task { await runVerification() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No article check yet", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Gemini compares the script to the blog post. HOOK lines are allowed to be dramatic; BODY, RELIEF, and CTA must match the article.")
        } actions: {
            Button("Compare with article") {
                Task { await runVerification() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.pipeline.isRunning)
        }
    }

    @ViewBuilder
    private func reportContent(_ report: ScriptVerificationReport) -> some View {
        VStack(spacing: 0) {
            summaryBanner(report)

            HSplitView {
                scriptLinesPanel
                    .frame(minWidth: 280)

                issueDetailPanel(report)
                    .frame(minWidth: 280)
            }
            .frame(maxHeight: .infinity)

            if hasGlobalSections(report) {
                Divider()
                globalSections(report)
                    .frame(maxHeight: 180)
            }
        }
    }

    private func summaryBanner(_ report: ScriptVerificationReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.verdict.icon)
                .font(.title2)
                .foregroundStyle(report.verdict.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.summary)
                    .font(.body)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    if let at = report.verifiedAt {
                        Text("Checked \(at)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let url = report.sourceURL, let link = URL(string: url) {
                        Link("Open article", destination: link)
                            .font(.caption)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(report.verdict.color.opacity(0.08))
    }

    private var scriptLinesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Script lines")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if visibleLines.isEmpty {
                Text(showIssuesOnly ? "No flagged lines — re-run check to confirm." : "No lines parsed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedVisibleLines, id: \.section) { group in
                            Text(group.section.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)
                                .padding(.horizontal, 12)

                            ForEach(group.lines) { annotated in
                                lineRow(annotated)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private struct SectionGroup {
        let section: ScriptSection
        let lines: [AnnotatedScriptLine]
    }

    private var groupedVisibleLines: [SectionGroup] {
        var order: [ScriptSection] = []
        var buckets: [ScriptSection: [AnnotatedScriptLine]] = [:]
        for item in visibleLines {
            if buckets[item.line.section] == nil {
                order.append(item.line.section)
                buckets[item.line.section] = []
            }
            buckets[item.line.section]?.append(item)
        }
        return order.map { SectionGroup(section: $0, lines: buckets[$0] ?? []) }
    }

    private func lineRow(_ annotated: AnnotatedScriptLine) -> some View {
        let isSelected = selectedLineID == annotated.id
        let severity = annotated.highestSeverity
        let showAsIssue = annotated.hasActiveIssue

        return Button {
            selectedLineID = annotated.id
            actionError = nil
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if annotated.isDisregarded {
                    Image(systemName: "eye.slash.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Image(systemName: showAsIssue ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(showAsIssue ? severity.color : .green)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(annotated.line.text)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(annotated.isDisregarded ? .secondary : .primary)
                        .strikethrough(annotated.isDisregarded, color: .secondary)

                    HStack(spacing: 6) {
                        Text(annotated.line.id)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        if annotated.isDisregarded {
                            Text("Disregarded")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if showAsIssue {
                            Text(severity.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(severity.color)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundFill(for: annotated, selected: isSelected))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor(for: annotated, selected: isSelected), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func backgroundFill(for annotated: AnnotatedScriptLine, selected: Bool) -> Color {
        if selected { return Color.accentColor.opacity(0.14) }
        if annotated.isDisregarded { return Color.secondary.opacity(0.06) }
        if annotated.hasActiveIssue { return annotated.highestSeverity.color.opacity(0.08) }
        return Color.clear
    }

    private func borderColor(for annotated: AnnotatedScriptLine, selected: Bool) -> Color {
        if selected { return Color.accentColor.opacity(0.5) }
        if annotated.isDisregarded { return Color.secondary.opacity(0.2) }
        if annotated.hasActiveIssue { return annotated.highestSeverity.color.opacity(0.35) }
        return Color.secondary.opacity(0.12)
    }

    @ViewBuilder
    private func issueDetailPanel(_ report: ScriptVerificationReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Why this matters")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView {
                if let selected = selectedAnnotation {
                    selectedLineDetail(selected)
                } else if report.verdict == .fail || report.verdict == .review {
                    overviewDetail(report)
                } else {
                    Text("Select a script line to see how it compares to the article.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func selectedLineDetail(_ annotated: AnnotatedScriptLine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(annotated.line.text)
                .font(.body.weight(.medium))
                .textSelection(.enabled)

            if annotated.isDisregarded {
                Label("You disregarded this finding — the line stays in the script.", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !annotated.lineIssues.isEmpty || !annotated.linkedIssues.isEmpty {
                    Text("Original finding")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(annotated.lineIssues) { issue in
                        issueCard(
                            title: issue.kind?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Issue",
                            severity: issue.issueSeverity,
                            note: issue.note ?? "",
                            muted: true
                        )
                    }
                    ForEach(annotated.linkedIssues) { issue in
                        issueCard(
                            title: issue.title,
                            severity: issue.issueSeverity,
                            note: issue.note ?? "",
                            muted: true
                        )
                    }
                }

                Button {
                    restoreIssue(annotated.line.id)
                } label: {
                    Label("Restore issue", systemImage: "arrow.uturn.backward")
                }
                .disabled(isBusy)
            } else if annotated.hasIssue {
                if !annotated.lineIssues.isEmpty {
                    ForEach(annotated.lineIssues) { issue in
                        issueCard(
                            title: issue.kind?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Issue",
                            severity: issue.issueSeverity,
                            note: issue.note ?? ""
                        )
                    }
                }

                ForEach(annotated.linkedIssues) { issue in
                    issueCard(
                        title: issue.title,
                        severity: issue.issueSeverity,
                        note: issue.note ?? ""
                    )
                }

                fixActions(for: annotated)
            } else {
                Label("Supported by the article", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func fixActions(for annotated: AnnotatedScriptLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fix this line")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                Button {
                    Task { await rewriteLine(annotated.line.id) }
                } label: {
                    Label("Rewrite with Gemini", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button {
                    disregardIssue(annotated.line.id)
                } label: {
                    Label("Disregard issue", systemImage: "eye.slash")
                }
                .disabled(isBusy)

                Button(role: .destructive) {
                    confirmDismissLineID = annotated.line.id
                } label: {
                    Label("Remove line", systemImage: "trash")
                }
                .disabled(isBusy)
            }

            Text("Disregard keeps the line but marks the finding as intentionally ignored. Rewrite or remove edits script.txt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func overviewDetail(_ report: ScriptVerificationReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap a highlighted line to rewrite it, remove it, or disregard the finding.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !report.unsupportedOrInvented.isEmpty {
                Text("Unsupported or invented")
                    .font(.subheadline.weight(.semibold))
                ForEach(report.unsupportedOrInvented) { issue in
                    issueCard(title: issue.title, severity: issue.issueSeverity, note: issue.note ?? "")
                }
            }

            if !report.recommendedFixes.isEmpty {
                Text("Recommended fixes")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(report.recommendedFixes.enumerated()), id: \.offset) { _, fix in
                    Text("• \(fix)")
                        .font(.callout)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func issueCard(title: String, severity: IssueSeverity, note: String, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(severity.label.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((muted ? Color.secondary : severity.color).opacity(0.2))
                    .foregroundStyle(muted ? .secondary : severity.color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(muted ? .secondary : .primary)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func hasGlobalSections(_ report: ScriptVerificationReport) -> Bool {
        !report.importantOmissions.isEmpty
            || report.ageConsistency?.ok == false
            || !report.supportedClaims.isEmpty
    }

    private func globalSections(_ report: ScriptVerificationReport) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                if !report.importantOmissions.isEmpty {
                    globalBox(title: "Missing from script") {
                        ForEach(report.importantOmissions) { issue in
                            issueCard(title: issue.title, severity: issue.issueSeverity, note: issue.note ?? "")
                        }
                    }
                }

                if let age = report.ageConsistency, age.ok != true {
                    globalBox(title: "Age mismatch") {
                        if let a = age.articleAge { Text("Article: \(a)").font(.caption) }
                        if let s = age.scriptAge { Text("Script: \(s)").font(.caption) }
                        if let n = age.note {
                            Text(n).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if !report.supportedClaims.isEmpty {
                    globalBox(title: "Supported claims") {
                        ForEach(Array(report.supportedClaims.prefix(6).enumerated()), id: \.offset) { _, claim in
                            Text("• \(claim)").font(.caption)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func globalBox<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
            content()
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @MainActor
    private func runVerification() async {
        isVerifying = true
        actionError = nil
        statusMessage = nil
        defer { isVerifying = false }
        do {
            try await store.verifyScript(current)
            reloadAll()
            refreshID = UUID()
            selectFirstIssueLine()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func dismissLine(_ lineID: String) async {
        actionError = nil
        isEditingLine = true
        defer { isEditingLine = false }
        do {
            try store.dismissScriptLine(current, lineID: lineID)
            report = nil
            reloadScript()
            statusMessage = "Line removed. Re-run check to verify the script against the article."
            selectedLineID = nil
            refreshID = UUID()
            selectFirstIssueLine()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func rewriteLine(_ lineID: String) async {
        actionError = nil
        isEditingLine = true
        defer { isEditingLine = false }
        do {
            let result = try await store.rewriteScriptLine(current, lineID: lineID)
            report = nil
            reloadScript()
            statusMessage = "Rewrote \(result.lineID): “\(result.newLine)” — re-run check to confirm."
            selectedLineID = lineID
            refreshID = UUID()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func disregardIssue(_ lineID: String) {
        actionError = nil
        do {
            try store.disregardVerificationIssue(current, lineID: lineID)
            reloadOverrides()
            statusMessage = "Finding disregarded for \(lineID). The script line is unchanged."
            refreshID = UUID()
            selectFirstIssueLine()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func restoreIssue(_ lineID: String) {
        actionError = nil
        do {
            try store.restoreVerificationIssue(current, lineID: lineID)
            reloadOverrides()
            statusMessage = "Restored issue for \(lineID)."
            refreshID = UUID()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func reloadAll() {
        reloadScript()
        report = current.loadScriptVerification()
        reloadOverrides()
        if report != nil, selectedLineID == nil {
            selectFirstIssueLine()
        }
    }

    private func reloadOverrides() {
        guard let report else {
            disregardedLineIDs = []
            return
        }
        disregardedLineIDs = current.loadVerificationOverrides(for: report)
    }

    private func reloadScript() {
        liveScript = current.loadScript()
    }

    private func selectFirstIssueLine() {
        guard report != nil else {
            selectedLineID = lines.first?.id
            return
        }
        selectedLineID = annotatedLines.first(where: \.hasActiveIssue)?.id ?? annotatedLines.first?.id
    }
}
