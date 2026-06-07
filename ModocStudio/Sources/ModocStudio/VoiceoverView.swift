import SwiftUI

struct VoiceoverView: View {
    let project: VideoProject

    private var speechText: String {
        let url = project.speechURL
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private var metaText: String {
        let url = project.voiceoverMetaURL
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        let audio = obj["audio_seconds"] as? Double ?? 0
        let video = obj["video_seconds"] as? Double ?? 0
        let pace = obj["pace"] as? String ?? "auto"
        return String(format: "Audio: %.1fs · Video: %.0fs · Pace: %@", audio, video, pace)
    }

    var body: some View {
        if project.hasVoiceover {
            VStack(alignment: .leading, spacing: 16) {
                MacAVPlayerView(url: project.voiceoverURL)
                    .frame(height: 48)

                if !metaText.isEmpty {
                    Text(metaText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Spoken script")
                    .font(.headline)

                ScrollView {
                    Text(speechText.isEmpty ? project.loadScript() : speechText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        } else {
            ContentUnavailableView(
                "No voiceover yet",
                systemImage: "waveform",
                description: Text("Generate voiceover from the Workflow tab after clip prompts.")
            )
        }
    }
}
