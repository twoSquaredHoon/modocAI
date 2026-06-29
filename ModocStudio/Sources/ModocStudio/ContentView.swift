import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        Group {
            switch store.appSection {
            case .home:
                HomeView()
            case .browse:
                BrowseProjectsView()
            case .pipeline:
                PipelineWorkspaceView()
            case .stats:
                GlobalStatsView()
            }
        }
    }
}
