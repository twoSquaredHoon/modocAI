import AppKit
import SwiftUI

extension Notification.Name {
    static let modocOpenExistingProject = Notification.Name("modocOpenExistingProject")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didInstallOpenShortcut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        scheduleOpenMenuShortcutInstall()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleOpenMenuShortcutInstall()
    }

    private func scheduleOpenMenuShortcutInstall() {
        guard !didInstallOpenShortcut else { return }
        DispatchQueue.main.async { [weak self] in
            self?.installOpenMenuShortcut()
        }
    }

    private func installOpenMenuShortcut() {
        guard !didInstallOpenShortcut else { return }
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.installOpenMenuShortcut()
            }
            return
        }

        if let existing = fileMenu.items.first(where: { $0.keyEquivalent == "o" }) {
            existing.target = self
            existing.action = #selector(openExistingProject(_:))
            existing.title = "Open Existing Project…"
        } else {
            let item = NSMenuItem(
                title: "Open Existing Project…",
                action: #selector(openExistingProject(_:)),
                keyEquivalent: "o"
            )
            item.target = self
            fileMenu.insertItem(item, at: min(1, fileMenu.items.count))
        }

        didInstallOpenShortcut = true
    }

    @objc private func openExistingProject(_ sender: Any?) {
        NotificationCenter.default.post(name: .modocOpenExistingProject, object: nil)
    }
}

@main
struct ModocStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 640)
                .onReceive(NotificationCenter.default.publisher(for: .modocOpenExistingProject)) { _ in
                    store.openExistingProject()
                }
                .sheet(isPresented: $store.showNewProjectSheet) {
                    NewProjectSheet()
                        .environmentObject(store)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") {
                    store.showNewProjectSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Open Existing Project…") {
                    store.openExistingProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
