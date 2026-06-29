import SwiftUI

struct BrowseProjectsView: View {
    @EnvironmentObject private var store: ProjectStore

    private var dateFolders: [ProjectBatchFolder] {
        store.ensureTodayInBatchFolders(store.batchFolders())
    }

    var body: some View {
        HStack(spacing: 0) {
            catalogPanel
                .frame(width: 400)
            Divider()
            detailPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if store.browseSelectedDateFolder == nil {
                store.browseSelectedDateFolder = dateFolders.first?.id
            }
            store.scheduleRefreshProjects(autoSelect: false)
        }
    }

    private var catalogPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Browse Projects")
                        .font(.largeTitle.bold())
                    Text("Pick a date, then open a project to edit scripts and clip prompts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if dateFolders.isEmpty {
                    ContentUnavailableView(
                        "No projects yet",
                        systemImage: "calendar",
                        description: Text("Run a daily batch or single video from Run Pipeline.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    datePickerRow
                    if let dateID = store.browseSelectedDateFolder {
                        dateProjectsContent(dateFolderID: dateID)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var datePickerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(dateFolders) { folder in
                        BrowseDateChip(
                            folder: folder,
                            isSelected: store.browseSelectedDateFolder == folder.id
                        ) {
                            store.browseSelectedDateFolder = folder.id
                            if folder.id != ProjectBatchFolder.legacyID {
                                let inFolder = store.projects(inBatchFolder: folder.id)
                                if !inFolder.contains(where: { $0.id == store.selectedProjectID }) {
                                    store.selectedProjectID = inFolder.first?.id
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dateProjectsContent(dateFolderID: String) -> some View {
        if dateFolderID == ProjectBatchFolder.legacyID {
            projectSection(title: "Other projects", projects: store.projects(inBatchFolder: dateFolderID))
        } else {
            let languages = store.languageFolders(in: dateFolderID)
            if languages.isEmpty {
                Text("No projects for this date yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(languages) { lang in
                    projectSection(
                        title: lang.displayTitle,
                        projects: store.projects(inBatchFolder: dateFolderID, languageFolder: lang.id)
                    )
                }
            }
        }
    }

    private func projectSection(title: String, projects: [VideoProject]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if projects.isEmpty {
                Text("No projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(projects) { project in
                        BrowseProjectCard(
                            project: project,
                            isSelected: store.selectedProjectID == project.id
                        ) {
                            store.selectedProjectID = project.id
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let project = store.selectedProject {
            ProjectDetailView(project: project)
        } else {
            ContentUnavailableView(
                "Select a project",
                systemImage: "film.stack",
                description: Text("Choose a project on the left to edit scripts, prompts, and run later pipeline steps.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private struct BrowseDateChip: View {
    let folder: ProjectBatchFolder
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Text(folder.isLegacy ? "Standalone" : folder.id)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                Text("\(folder.projectCount) project\(folder.projectCount == 1 ? "" : "s")")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BrowseProjectCard: View {
    let project: VideoProject
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.manifest.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        PhaseBadge(phase: project.manifest.phase)
                        LanguageBadge(language: project.manifest.language)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
