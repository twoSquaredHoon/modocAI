import SwiftUI

struct CustomBatchSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var options = CustomBatchOptions()
    @State private var errorMessage: String?
    @State private var isStarting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Custom Batch")
                    .font(.title2.bold())

                Text("Fetch a chosen number of blog posts in your language, then run the pipeline steps you want.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                sectionTitle("Fetch")
                fetchSection

                sectionTitle("Pipeline steps")
                pipelineSection

                sectionTitle("Output")
                outputSection

                summaryBox

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

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isStarting)
                    Button("Start Custom Batch") {
                        startBatch()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isStarting || !ModocConfig.hasVenv || !options.hasLanguageSelection)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 640)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var fetchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Fetch by", selection: $options.fetchMode) {
                ForEach(CustomBatchFetchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(options.fetchMode == .newest ? "Number of articles" : "Max per language")
                    .frame(width: 160, alignment: .leading)
                Stepper(value: $options.articleCount, in: 1...50) {
                    Text("\(options.articleCount)")
                        .monospacedDigit()
                }
            }

            if options.fetchMode == .recent {
                HStack {
                    Text("Time window (hours)")
                        .frame(width: 160, alignment: .leading)
                    Stepper(value: $options.sinceHours, in: 1...720) {
                        Text("\(options.sinceHours) h")
                            .monospacedDigit()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Languages")
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 20) {
                    Toggle(isOn: $options.includeEnglish) {
                        HStack(spacing: 6) {
                            LanguageBadge(language: .en)
                            Text("English")
                        }
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $options.includeKorean) {
                        HStack(spacing: 6) {
                            LanguageBadge(language: .ko)
                            Text("Korean")
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                if !options.hasLanguageSelection {
                    Text("Select at least one language.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Toggle("Include already processed articles", isOn: $options.includeProcessed)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pipeline cap")
                        .frame(width: 160, alignment: .leading)
                    Stepper(value: $options.processingLimit, in: 0...100) {
                        Text(options.processingLimit == 0 ? "No cap" : "\(options.processingLimit) URLs")
                            .monospacedDigit()
                    }
                }
                Text("Fetch may return many URLs; this limits how many actually run through the pipeline. No cap = run all fetched URLs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(fieldBackground)
    }

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Article check (script vs blog)", isOn: $options.runArticleCheck)
            Toggle("Voiceover (Gemini TTS)", isOn: $options.runVoiceover)
            Toggle("Veo videos (paid API)", isOn: $options.runVideos)

            if options.runVideos {
                Label("Veo generation uses paid API credits.", systemImage: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Script and clip prompts always run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(fieldBackground)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Batch folder")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(options.dateFolderID)
                    .font(.caption.monospaced())
            }
            Button("Regenerate folder name") {
                options.dateFolderID = BatchRunner.customFolderID()
            }
            .font(.caption)
            .buttonStyle(.link)
        }
        .padding(14)
        .background(fieldBackground)
    }

    private var summaryBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(options.fetchSummary)
                .font(.callout)
            Text("Pipeline: \(options.pipelineSummary)")
                .font(.callout)
            Text(options.processingLimitSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private func startBatch() {
        errorMessage = nil
        guard options.hasLanguageSelection else {
            errorMessage = "Select at least one language."
            return
        }
        isStarting = true
        defer { isStarting = false }

        do {
            try store.startCustomBatch(options: options)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
