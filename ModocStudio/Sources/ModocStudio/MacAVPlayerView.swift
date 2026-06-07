import AVKit
import AppKit
import SwiftUI

/// AppKit AVPlayerView — SwiftUI VideoPlayer often crashes on macOS in split views.
struct MacAVPlayerView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.showsSharingServiceButton = false
        let player = AVPlayer(url: url)
        view.player = player
        context.coordinator.player = player
        context.coordinator.currentURL = url
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        view.player?.pause()
        let player = AVPlayer(url: url)
        view.player = player
        context.coordinator.player = player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
        coordinator.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        var currentURL: URL?
    }
}
