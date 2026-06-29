import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore

    private var sectionTitle: String {
        switch store.appSection {
        case .home: return "Modoc Studio"
        case .browse: return "Browse Projects"
        case .pipeline: return "Run Pipeline"
        case .stats:
            switch store.statsSubsection {
            case .hub: return "Stats"
            case .projects: return "Completed Articles"
            case .time: return "Pipeline Time"
            }
        }
    }

    var body: some View {
        ZStack {
            HomeView()
                .opacity(store.appSection == .home ? 1 : 0)
                .allowsHitTesting(store.appSection == .home)

            BrowseProjectsView()
                .opacity(store.appSection == .browse ? 1 : 0)
                .allowsHitTesting(store.appSection == .browse)

            PipelineWorkspaceView()
                .opacity(store.appSection == .pipeline ? 1 : 0)
                .allowsHitTesting(store.appSection == .pipeline)

            GlobalStatsView()
                .opacity(store.appSection == .stats ? 1 : 0)
                .allowsHitTesting(store.appSection == .stats)
        }
        .navigationTitle(sectionTitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if store.appSection == .stats, store.statsSubsection != .hub {
                    Button {
                        store.statsGoToHub()
                    } label: {
                        Label("Stats", systemImage: "chevron.left")
                    }
                    .help("Back to Stats")
                }

                if store.appSection != .home {
                    Button {
                        store.goHome()
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                    .help("Back to home")
                }
            }

            if store.appSection == .browse {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        if store.isRefreshingProjects {
                            ProgressView().controlSize(.small)
                        }
                        Button {
                            store.scheduleRefreshProjects(autoSelect: false, delayMs: 0)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh projects")
                    }
                }
            }

            if store.appSection == .stats {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.requestStatsRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh stats")
                }
            }
        }
    }
}
