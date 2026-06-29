import SwiftUI

enum AppSection: String, Hashable {
    case home
    case browse
    case pipeline
    case stats
}

struct ProjectBatchFolder: Identifiable, Hashable {
    static let legacyID = "__legacy__"

    let id: String
    let displayTitle: String
    let projectCount: Int
    let sortKey: String

    var isLegacy: Bool { id == Self.legacyID }
}

struct ProjectBatchLanguageFolder: Identifiable, Hashable {
    let id: String
    let displayTitle: String
    let projectCount: Int
    let language: ProjectLanguage
}

struct HomeView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("Modoc Studio")
                    .font(.largeTitle.bold())
                Text("Choose where to go")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            HStack(spacing: 20) {
                HomeDestinationCard(
                    title: "Browse Projects",
                    subtitle: "Open batch folders by date and review finished work",
                    systemImage: "calendar",
                    tint: .blue
                ) {
                    store.enterBrowse()
                }

                HomeDestinationCard(
                    title: "Run Pipeline",
                    subtitle: "Create a project, run steps, and edit scripts and clips",
                    systemImage: "play.circle.fill",
                    tint: .orange
                ) {
                    store.enterPipeline()
                }

                HomeDestinationCard(
                    title: "Stats",
                    subtitle: "Timing and pipeline history across all projects",
                    systemImage: "chart.bar.fill",
                    tint: .green
                ) {
                    store.enterStats()
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HomeDestinationCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 36))
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
}

struct HomeToolbar: ViewModifier {
    @EnvironmentObject private var store: ProjectStore
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        store.goHome()
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                    .help("Back to home")
                }
            }
    }
}

extension View {
    func withHomeToolbar(title: String) -> some View {
        modifier(HomeToolbar(title: title))
    }
}

enum ProjectBatchFolderFormat {
    static let englishFolder = "english"
    static let koreanFolder = "korean"
    static let spanishFolder = "spanish"

    static let languageFolderOrder = [englishFolder, koreanFolder, spanishFolder]

    static func folderName(for language: ProjectLanguage) -> String {
        switch language {
        case .en: return englishFolder
        case .ko: return koreanFolder
        case .es: return spanishFolder
        }
    }

    static func language(for folderName: String) -> ProjectLanguage? {
        switch folderName {
        case englishFolder: return .en
        case koreanFolder: return .ko
        case spanishFolder: return .es
        case "en": return .en
        case "ko": return .ko
        case "es": return .es
        default: return nil
        }
    }

    static func displayTitle(forLanguageFolder folderName: String) -> String {
        switch folderName {
        case englishFolder, "en": return "English"
        case koreanFolder, "ko": return "한국어 (Korean)"
        case spanishFolder, "es": return "Español (Spanish)"
        default: return folderName.capitalized
        }
    }

    private static let folderDate = DateFormatter()

    static func displayTitle(for folderName: String) -> String {
        folderDate.dateFormat = "yyyy-MM-dd"
        guard let date = folderDate.date(from: folderName) else { return folderName }
        let display = DateFormatter()
        display.dateStyle = .long
        display.timeStyle = .none
        return display.string(from: date)
    }

    static func isDateBatchFolder(_ name: String) -> Bool {
        name.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}
