import SwiftUI

struct RunPipelineHubView: View {
    @EnvironmentObject private var store: ProjectStore

    private var todayID: String { BatchRunner.todayFolderID() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                HStack(alignment: .top, spacing: 20) {
                    creationCard(
                        title: "Single Video",
                        subtitle: "Paste one blog URL and run the full pipeline automatically — script, article check, clip prompts, voiceover, and Veo videos.",
                        systemImage: "1.circle.fill",
                        tint: .orange
                    ) {
                        store.showNewProjectSheet = true
                    }

                    creationCard(
                        title: "Daily Batch",
                        subtitle: "Fetch English and Korean posts from the last 24 hours. Creates scripts and clip prompts only — review and finish in Browse Projects.",
                        systemImage: "calendar.badge.clock",
                        tint: .blue
                    ) {
                        store.startDailyBatch(dateFolderID: todayID)
                    }
                }

                browseHint
            }
            .padding(32)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run Pipeline")
                .font(.largeTitle.bold())
            Text("Choose how to create new content.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var browseHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text("Open Browse Projects to edit scripts, add clip prompts, run voiceover, and generate videos when you are ready.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func creationCard(
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
                Text("Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
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
}
