import SwiftUI

struct BrowseProjectsView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        NavigationSplitView {
            dateSidebar
        } content: {
            languageAndProjects
        } detail: {
            browseDetail
        }
        .withHomeToolbar(title: "Browse Projects")
        .onAppear {
            store.refreshProjects()
            if store.browseSelectedDateFolder == nil {
                store.browseSelectedDateFolder = store.ensureTodayInBatchFolders(store.batchFolders()).first?.id
            }
            store.syncBrowseLanguageSelection()
        }
        .onChange(of: store.browseSelectedDateFolder) { _, _ in
            store.syncBrowseLanguageSelection()
        }
        .onChange(of: store.browseSelectedLanguageFolder) { _, _ in
            store.syncBrowseLanguageSelection()
        }
    }

    private var dateSidebar: some View {
        List(selection: $store.browseSelectedDateFolder) {
            Section("Dates") {
                if store.batchFolders().isEmpty {
                    Text("No batch folders yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.ensureTodayInBatchFolders(store.batchFolders())) { folder in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayTitle)
                                .font(.headline)
                            Text(folder.isLegacy ? "Individual projects" : folder.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(folder.projectCount)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .tag(folder.id)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button {
                    store.refreshProjects()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh folders")
            }
        }
    }

    @ViewBuilder
    private var languageAndProjects: some View {
        if let folderID = store.browseSelectedDateFolder {
            if folderID == ProjectBatchFolder.legacyID {
                legacyProjectList
            } else {
                datedBatchContent(dateFolderID: folderID)
            }
        } else {
            ContentUnavailableView(
                "Select a date",
                systemImage: "calendar",
                description: Text("Choose a batch date on the left.")
            )
        }
    }

    @ViewBuilder
    private func datedBatchContent(dateFolderID: String) -> some View {
        let languages = store.languageFolders(in: dateFolderID)
        let projects: [VideoProject] = {
            guard let langID = store.browseSelectedLanguageFolder else { return [] }
            return store.projects(inBatchFolder: dateFolderID, languageFolder: langID)
        }()

        VStack(spacing: 0) {
            BatchStatusBanner(dateFolderID: dateFolderID)

            List(selection: $store.browseSelectedLanguageFolder) {
                Section("Language") {
                    if languages.isEmpty {
                        Text("No projects in this batch")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(languages) { lang in
                        HStack {
                            LanguageBadge(language: lang.language)
                            Text(lang.displayTitle)
                                .font(.headline)
                            Spacer()
                            Text("\(lang.projectCount)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .tag(lang.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(maxHeight: 160)

            Divider()

            List(selection: $store.selectedProjectID) {
                Section("Projects") {
                    if projects.isEmpty {
                        Text("Select a language folder")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(projects) { project in
                        ProjectRow(project: project)
                            .tag(project.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 300)
    }

    private var legacyProjectList: some View {
        List(selection: $store.selectedProjectID) {
            Section("Other projects") {
                ForEach(store.projects(inBatchFolder: ProjectBatchFolder.legacyID)) { project in
                    ProjectRow(project: project)
                        .tag(project.id)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 300)
    }

    @ViewBuilder
    private var browseDetail: some View {
        if let project = store.selectedProject {
            ProjectDetailView(project: project)
        } else {
            ContentUnavailableView(
                "Select a project",
                systemImage: "film.stack",
                description: Text("Pick English or Korean, then choose a project.")
            )
        }
    }
}
