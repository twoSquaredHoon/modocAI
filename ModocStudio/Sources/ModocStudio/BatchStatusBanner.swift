import SwiftUI

struct BatchStatusBanner: View {
    let dateFolderID: String
    @EnvironmentObject private var store: ProjectStore
    @State private var batchState: BatchStateFile?
    @State private var inferred: InferredBatchProgress?
    @State private var refreshTimer: Timer?

    private var batchFolderURL: URL {
        ModocConfig.projectsURL.appendingPathComponent(dateFolderID, isDirectory: true)
    }

    private var projects: [VideoProject] {
        store.projects(inBatchFolder: dateFolderID)
    }

    private var needsResume: Bool {
        store.batchNeedsResume(for: dateFolderID)
    }

    private var isRunningLive: Bool {
        store.batchIsRunning(for: dateFolderID)
    }

    private var canStartBatch: Bool {
        !isRunningLive && !needsResume
            && (batchState?.effectiveStatus != .completed)
    }

    var body: some View {
        Group {
            batchPanel
        }
        .onAppear { reload() }
        .onDisappear { refreshTimer?.invalidate() }
        .onChange(of: dateFolderID) { _, _ in reload() }
    }

    private var batchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily batch")
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let progress = progressLabel {
                    Text(progress)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }

            if let batchState, let current = batchState.current, !current.step.isEmpty {
                let line = batchState.total > 0 && current.index > 0
                    ? "[\(current.index)/\(batchState.total)] \(current.step)"
                    : current.step
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let batchState, batchState.total > 0 {
                HStack(spacing: 16) {
                    miniStat("Done", batchState.completed)
                    miniStat("Failed", batchState.failed)
                    miniStat("Skipped", batchState.skipped)
                }
            } else if let inferred {
                HStack(spacing: 16) {
                    miniStat("Ready", inferred.ready)
                    miniStat("In progress", inferred.inProgress)
                    miniStat("Failed", inferred.failed)
                    if inferred.finishedCount < inferred.total {
                        miniStat("Remaining", inferred.total - inferred.finishedCount)
                    }
                }
            }

            if let err = batchState?.lastError, !err.isEmpty, batchState?.effectiveStatus != .running {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if isRunningLive {
                    ProgressView().controlSize(.small)
                    Text("Running…")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if needsResume {
                    Button {
                        store.resumeDailyBatch(dateFolderID: dateFolderID)
                    } label: {
                        Label("Resume Batch", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else if canStartBatch {
                    Button {
                        store.startDailyBatch(dateFolderID: dateFolderID)
                    } label: {
                        Label("Start Daily Batch", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    store.revealBatchLog(in: dateFolderID)
                } label: {
                    Label("View Log", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(statusColor.opacity(0.1)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusIcon: String {
        if isRunningLive { return "arrow.trianglehead.2.clockwise.rotate.90" }
        if needsResume { return "exclamationmark.triangle.fill" }
        if batchState?.effectiveStatus == .completed { return "checkmark.circle.fill" }
        return "tray.full.fill"
    }

    private var statusColor: Color {
        if isRunningLive { return .orange }
        if needsResume { return .orange }
        if batchState?.effectiveStatus == .completed { return .green }
        return .secondary
    }

    private var statusSubtitle: String {
        if isRunningLive { return "Batch is running" }
        if let state = batchState {
            return "Status: \(state.effectiveStatus.label)"
        }
        if needsResume { return "Batch incomplete — tap Resume to continue" }
        return "Batch finished"
    }

    private var progressLabel: String? {
        if let state = batchState { return state.progressLabel }
        if let inferred { return "\(inferred.finishedCount)/\(inferred.total)" }
        return nil
    }

    private func miniStat(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private func reload() {
        batchState = BatchStateReader.load(from: batchFolderURL)
        inferred = BatchStateReader.inferProgress(in: batchFolderURL, projects: projects)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                batchState = BatchStateReader.load(from: batchFolderURL)
                inferred = BatchStateReader.inferProgress(in: batchFolderURL, projects: projects)
                store.refreshProjects(autoSelect: false)
            }
        }
    }
}
