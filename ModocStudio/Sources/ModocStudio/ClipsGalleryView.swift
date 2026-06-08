import SwiftUI

struct ClipsGalleryView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: VideoProject
    let clips: [ClipRecord]
    @Binding var selectedClipID: String?

    @State private var regenError: String?
    @State private var isRegenerating = false
    @State private var playerKey = UUID()
    @State private var confirmRegenerateAll = false

    private var current: VideoProject {
        store.selectedProject ?? project
    }

    private var videoStatus: (done: Int, total: Int) {
        current.videoStatus(for: clips)
    }

    var body: some View {
        if clips.isEmpty {
            ContentUnavailableView(
                "No clips yet",
                systemImage: "film",
                description: Text("Generate clip prompts and videos from the Workflow tab.")
            )
        } else {
            VStack(spacing: 0) {
                clipsToolbar
                Divider()
                HSplitView {
                    clipList
                        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
                    clipPreview
                        .frame(minWidth: 320, minHeight: 280)
                }
            }
        }
    }

    private var clipsToolbar: some View {
        HStack(spacing: 12) {
            Text("\(videoStatus.done)/\(videoStatus.total) clips generated")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if isRegeneratingAllClips {
                ProgressView()
                    .controlSize(.small)
                Text("Regenerating all clips…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                confirmRegenerateAll = true
            } label: {
                Label("Regenerate all clips", systemImage: "arrow.clockwise.circle")
            }
            .disabled(!current.hasClipsJSON || store.pipeline.isRunning || isRegenerating)
            .confirmationDialog(
                "Regenerate all \(clips.count) clips?",
                isPresented: $confirmRegenerateAll,
                titleVisibility: .visible
            ) {
                Button("Regenerate all (\(clips.count) clips, Veo paid)", role: .destructive) {
                    Task { await regenerateAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes every existing clip video and generates them again from the current prompts.")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var clipList: some View {
        List(clips, selection: $selectedClipID) { clip in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.label)
                        .font(.subheadline.weight(.medium))
                    Text(clip.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRegeneratingAllClips {
                    ProgressView()
                        .controlSize(.mini)
                } else if hasVideo(clip.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .tag(clip.id)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var clipPreview: some View {
        if let id = selectedClipID, let clip = clips.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(clip.label)
                        .font(.title3.bold())
                    Spacer()
                    regenerateButton(for: id)
                }
                .padding(.horizontal)

                if let regenError {
                    Text(regenError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if isRegeneratingClip(id) {
                    HStack {
                        ProgressView()
                        Text(regeneratingMessage(for: id))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasVideo(id) {
                    MacAVPlayerView(url: current.videoURL(for: id))
                        .frame(minHeight: 240, maxHeight: .infinity)
                        .padding(.horizontal)
                        .id(playerKey)
                } else {
                    ContentUnavailableView(
                        "Not generated",
                        systemImage: "video.slash",
                        description: Text("Tap Regenerate clip to create this video.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let prompt = clip.veoPrompt ?? clip.detailedPrompt {
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        } else {
            ContentUnavailableView("Select a clip", systemImage: "play.rectangle")
        }
    }

    @ViewBuilder
    private func regenerateButton(for clipId: String) -> some View {
        Button {
            Task { await regenerate(clipId: clipId) }
        } label: {
            Label("Regenerate clip", systemImage: "arrow.clockwise")
        }
        .disabled(!current.hasClipsJSON || store.pipeline.isRunning || isRegenerating)
    }

    private func regeneratingMessage(for clipId: String) -> String {
        if isRegeneratingAllClips {
            return "Regenerating all clips… (\(clipId) may be in queue)"
        }
        return "Regenerating \(clipId)… (Veo, paid)"
    }

    private var isRegeneratingAllClips: Bool {
        store.pipeline.runningStep == .regenerateAllClips
    }

    private func isRegeneratingClip(_ clipId: String) -> Bool {
        if isRegeneratingAllClips { return true }
        if case .regenerateClip(let id) = store.pipeline.runningStep {
            return id == clipId
        }
        return isRegenerating
    }

    private func regenerate(clipId: String) async {
        regenError = nil
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            try await store.runWorkflowStep(current, step: .regenerateClip(clipId))
            playerKey = UUID()
            store.refreshProjects()
        } catch {
            regenError = error.localizedDescription
        }
    }

    private func regenerateAll() async {
        regenError = nil
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            try await store.runWorkflowStep(current, step: .regenerateAllClips)
            playerKey = UUID()
            store.refreshProjects()
        } catch {
            regenError = error.localizedDescription
        }
    }

    private func hasVideo(_ clipID: String) -> Bool {
        let url = current.videoURL(for: clipID)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return false }
        return size > 1000
    }
}
