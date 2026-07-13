// High-pass filter + dual-EMA onset slap detector.

import Foundation

public struct SlapEvent: Sendable {
    public let amplitude: Double
    public let timestamp: TimeInterval

    public init(amplitude: Double, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.amplitude = amplitude
        self.timestamp = timestamp
    }
}

/// Removes gravity, then detects slap onsets via fast/slow energy ratio.
public final class SlapDetector: @unchecked Sendable {
    public var onSlap: ((SlapEvent) -> Void)?

    /// Minimum amplitude (g residual) to emit a slap.
    public var minAmplitude: Double
    /// Cooldown between emitted slaps, in seconds.
    public var cooldownSeconds: Double

    private let sampleRate: Int
    private let hpAlpha: Double = 0.95
    private var hpPrevRaw: (Double, Double, Double) = (0, 0, 0)
    private var hpPrevOut: (Double, Double, Double) = (0, 0, 0)
    private var hpReady = false

    private var fast: Double = 0
    private var slow: Double = 0
    private let fastAlpha: Double
    private let slowAlpha: Double
    private let onsetRatio: Double = 3.0

    private var warmupRemaining: Int
    private var cooldownRemaining: Int = 0
    private var lastEmit: TimeInterval = 0

    public init(sampleRate: Int = 100, minAmplitude: Double = 0.05, cooldownSeconds: Double = 0.65) {
        self.sampleRate = sampleRate
        self.minAmplitude = minAmplitude
        self.cooldownSeconds = cooldownSeconds
        self.warmupRemaining = sampleRate

        let fastWindow = max(sampleRate / 20, 2)
        self.fastAlpha = 2.0 / (Double(fastWindow) + 1.0)
        let slowWindow = max(sampleRate / 2, 2)
        self.slowAlpha = 2.0 / (Double(slowWindow) + 1.0)
    }

    public func process(x ax: Double, y ay: Double, z az: Double) {
        let mag: Double
        if !hpReady {
            hpPrevRaw = (ax, ay, az)
            hpReady = true
            mag = 0
        } else {
            let a = hpAlpha
            let hx = a * (hpPrevOut.0 + ax - hpPrevRaw.0)
            let hy = a * (hpPrevOut.1 + ay - hpPrevRaw.1)
            let hz = a * (hpPrevOut.2 + az - hpPrevRaw.2)
            hpPrevRaw = (ax, ay, az)
            hpPrevOut = (hx, hy, hz)
            mag = (hx * hx + hy * hy + hz * hz).squareRoot()
        }

        let e = mag * mag
        fast += fastAlpha * (e - fast)
        slow += slowAlpha * (e - slow)

        if warmupRemaining > 0 {
            warmupRemaining -= 1
            return
        }

        if cooldownRemaining > 0 {
            cooldownRemaining -= 1
            return
        }

        let ratio = fast / (slow + 1e-20)
        let amp = fast.squareRoot()
        guard ratio > onsetRatio, amp >= minAmplitude else { return }

        let now = Date().timeIntervalSince1970
        guard now - lastEmit >= cooldownSeconds else { return }

        lastEmit = now
        cooldownRemaining = max(1, Int(cooldownSeconds * Double(sampleRate)))
        onSlap?(SlapEvent(amplitude: amp, timestamp: now))
    }
}
