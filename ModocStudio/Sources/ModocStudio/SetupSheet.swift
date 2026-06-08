import SwiftUI

struct SetupSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up Modoc Studio")
                .font(.title2.bold())

            Text(
                "Something is missing for a fresh install. Run ./setup.sh once from your modocAI folder, then ./build-modoc-studio.sh. "
                    + "If you moved or renamed the repo, choose the modocAI folder below."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            GroupBox("Current folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ModocConfig.rootURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    ForEach(Array(ModocConfig.setupIssues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if ModocConfig.setupIssues.isEmpty {
                        Label("Ready — projects folder is writable.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Choose modocAI Folder…") {
                    store.chooseModocRoot()
                }
                .buttonStyle(.borderedProminent)

                if ModocConfig.rootExists {
                    Button("Run setup in Terminal") {
                        store.openSetupInstructionsInTerminal()
                    }
                }

                Spacer()

                Button("Continue") {
                    dismiss()
                }
                .disabled(ModocConfig.needsSetup)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
