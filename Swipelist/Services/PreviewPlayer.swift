import AVFoundation
import Foundation

/// Plays 30-second track previews and publishes playback progress (0...1).
@MainActor
final class PreviewPlayer: ObservableObject {
    @Published private(set) var progress: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    func play(_ url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.updateProgress(time)
            }
        }
        player.play()
    }

    func setPaused(_ paused: Bool) {
        if paused { player?.pause() } else { player?.play() }
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        progress = 0
    }

    private func updateProgress(_ time: CMTime) {
        guard let duration = player?.currentItem?.duration.seconds,
              duration.isFinite, duration > 0 else { return }
        progress = min(1, time.seconds / duration)
    }
}
