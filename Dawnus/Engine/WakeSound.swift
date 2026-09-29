import AVFoundation
import UIKit

/// 真正的响铃播放：用 AVAudioSession 的 playback 分类，
/// 配合 AlarmKit 的系统闹钟可以压过静音开关与专注模式。
final class WakeSound: @unchecked Sendable {
    static let shared = WakeSound()

    private var player: AVAudioPlayer?
    private var configured = false

    private init() {}

    func start() {
        configureSession()
        guard let url = Bundle.main.url(forResource: "dawn", withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url)
        else {
            // 资源缺失时用系统震动兜底，保证至少「有反馈」
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        p.numberOfLoops = -1
        p.volume = 1.0
        // 3 秒内淡入，避免被吓醒
        p.play()
        p.setVolume(0.05, fadeDuration: 0)
        p.setVolume(1.0, fadeDuration: 3)
        player = p
    }

    func stop() {
        player?.setVolume(0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.player?.stop()
            self?.player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func configureSession() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }
}
