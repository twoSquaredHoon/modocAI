import AVKit
import AppKit
import SwiftUI

/// AppKit AVPlayerView — SwiftUI VideoPlayer often crashes on macOS in split views.
struct MacAVPlayerView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.showsSharingServiceButton = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let player = AVPlayer(url: url)
        view.player = player
        context.coordinator.player = player
        context.coordinator.playerView = view
        context.coordinator.currentURL = url
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let view = context.coordinator.playerView else { return }
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        view.player?.pause()
        let player = AVPlayer(url: url)
        view.player = player
        context.coordinator.player = player
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.playerView?.player?.pause()
        coordinator.playerView?.player = nil
        coordinator.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        var playerView: AVPlayerView?
        var currentURL: URL?
    }
}
