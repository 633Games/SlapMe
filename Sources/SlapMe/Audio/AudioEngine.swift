import AVFoundation
import Foundation

enum AudioEngineError: LocalizedError {
    case emptyPack
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyPack: return "Sound pack has no audio files"
        case .loadFailed(let msg): return msg
        }
    }
}

final class AudioEngine {
    private var player: AVAudioPlayer?
    private var previewPlayer: AVPlayer?
    private var recent: [URL] = []

    func playRandom(from pack: SoundPack, volume: Double) throws {
        stopPreview()
        guard !pack.files.isEmpty else { throw AudioEngineError.emptyPack }

        let candidates = pack.files.filter { !recent.contains($0) }
        let pool = candidates.isEmpty ? pack.files : candidates
        guard let url = pool.randomElement() else { throw AudioEngineError.emptyPack }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = Float(max(0, min(1, volume)))
            p.prepareToPlay()
            p.play()
            player = p
            recent.append(url)
            if recent.count > max(1, pack.files.count - 1) {
                recent.removeFirst()
            }
        } catch {
            throw AudioEngineError.loadFailed(error.localizedDescription)
        }
    }

    /// Stream a remote clip for soundboard preview (does not save it).
    func previewRemote(url: URL, volume: Double = 0.9) {
        player?.stop()
        player = nil
        stopPreview()

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = Float(max(0, min(1, volume)))
        p.play()
        previewPlayer = p
    }

    func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
    }
}
