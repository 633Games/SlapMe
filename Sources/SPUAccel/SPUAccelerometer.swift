import Foundation

/// High-level accelerometer + slap detection API.
public final class SPUAccelerometer: @unchecked Sendable {
    public var onSample: ((IMUSample) -> Void)?
    public var onSlap: ((SlapEvent) -> Void)?

    public let detector: SlapDetector
    public var callbackQueue: DispatchQueue

    private let driver = SPUDriver()
    private var sensorThread: Thread?
    private var isRunning = false

    public init(
        sampleRate: Int = 100,
        minAmplitude: Double = 0.05,
        cooldownSeconds: Double = 0.65,
        callbackQueue: DispatchQueue = .main
    ) {
        self.callbackQueue = callbackQueue
        self.detector = SlapDetector(
            sampleRate: sampleRate,
            minAmplitude: minAmplitude,
            cooldownSeconds: cooldownSeconds
        )
        self.detector.onSlap = { [weak self] event in
            guard let self else { return }
            self.callbackQueue.async {
                self.onSlap?(event)
            }
        }
    }

    public func start() throws {
        guard getuid() == 0 else { throw SPUError.needsRoot }
        guard !isRunning else { return }
        isRunning = true

        let errorBox = UnsafeMutablePointer<Error?>.allocate(capacity: 1)
        errorBox.initialize(to: nil)
        let semaphore = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            guard let self else { return }
            do {
                try self.driver.start { [weak self] sample in
                    guard let self else { return }
                    self.detector.process(x: sample.gX, y: sample.gY, z: sample.gZ)
                    self.callbackQueue.async {
                        self.onSample?(sample)
                    }
                }
            } catch {
                errorBox.pointee = error
                semaphore.signal()
            }
        }
        thread.name = "com.slapme.sensor"
        thread.qualityOfService = .userInteractive
        sensorThread = thread
        thread.start()

        if semaphore.wait(timeout: .now() + 1.5) == .success, let error = errorBox.pointee {
            errorBox.deallocate()
            isRunning = false
            throw error
        }
        errorBox.deallocate()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        driver.stop()
        sensorThread = nil
    }
}
