import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    store.showNewProjectSheet = true
                } label: {
                    Label("New Project", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    store.openExistingProject()
                } label: {
                    Label("Open Existing Project", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(12)

            Divider()

            List(selection: $store.selectedProjectID) {
                Section("Projects") {
                    if store.projects.isEmpty {
                        Text("No projects yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.projects) { project in
                        ProjectRow(project: project)
                            .tag(project.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Modoc Studio")
        .toolbar {
            ToolbarItem {
                Button {
                    store.refreshProjects()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh projects")
            }
        }
    }
}

struct ProjectRow: View {
    let project: VideoProject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.manifest.title)
                .lineLimit(2)
                .font(.headline)
            HStack(spacing: 6) {
                PhaseBadge(phase: project.manifest.phase)
                Text(project.manifest.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PhaseBadge: View {
    let phase: ProjectPhase

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch phase {
        case .creatingScript: return "Writing script"
        case .scriptReview: return "Review script"
        case .generatingPrompts: return "Building prompts"
        case .promptsReview: return "Review prompts"
        case .generatingVoiceover: return "Voiceover"
        case .voiceoverReview: return "Review voiceover"
        case .generatingVideos: return "Generating clips"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    private var color: Color {
        switch phase {
        case .ready: return .green
        case .failed: return .red
        case .creatingScript, .generatingPrompts, .generatingVoiceover, .generatingVideos: return .orange
        default: return .blue
        }
    }
}
