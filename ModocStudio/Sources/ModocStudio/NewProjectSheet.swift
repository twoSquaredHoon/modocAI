import AppKit
import SwiftUI

struct NewProjectSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var language: ProjectLanguage = .en
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var focusField = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title2.bold())

            Text("Paste a FeverCoach blog URL. The script generates automatically; you review before clip prompts and videos.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Language")
                    .font(.subheadline.weight(.medium))

                Picker("Language", selection: $language) {
                    ForEach(ProjectLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isCreating)

                Text("Script and voiceover use this language. Clip prompts use matching family appearance (see visual_cast.txt).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Blog URL")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    MacTextField(
                        text: $urlText,
                        placeholder: "Paste URL here",
                        isEnabled: !isCreating,
                        autofocus: focusField,
                        onSubmit: {
                            if canCreate { Task { await create() } }
                        }
                    )
                    .frame(height: 28)

                    Button("Paste") {
                        pasteFromClipboard()
                    }
                    .disabled(isCreating)
                }

                Text("Example: https://www.fevercoach.us/post/your-article-slug")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !ModocConfig.hasVenv {
                Label("Run ./setup.sh in the modocAI folder first.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if isCreating || store.pipeline.isRunning {
                HStack {
                    ProgressView()
                    Text("Generating script…")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create & Generate Script") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            focusField = true
        }
    }

    private var canCreate: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    private func pasteFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }
        urlText = value
        focusField = true
    }

    private func create() async {
        errorMessage = nil
        isCreating = true
        defer { isCreating = false }

        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("http") else {
            errorMessage = "URL must start with http:// or https://"
            return
        }

        do {
            try await store.createProject(blogURL: url, language: language)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
