import Foundation
import AVFoundation
import SoundStageCore

enum AutoSyncError: LocalizedError {
    case notRunning
    case needTwoDevices
    case micDenied
    case micUnavailable(String)
    case lowConfidence(device: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Start SoundStage before Autosync."
        case .needTwoDevices:
            return "Enable at least two output devices to Autosync."
        case .micDenied:
            return "Microphone access is required for Autosync. Allow it in System Settings › Privacy & Security › Microphone."
        case .micUnavailable(let detail):
            return "Could not open the microphone: \(detail)"
        case .lowConfidence(let device):
            return "Couldn’t lock onto \(device). Move the Mac nearer your listening spot, raise volume, and try a quieter room."
        case .cancelled:
            return nil
        }
    }
}

/// One-shot mic capture from the system default input.
final class MicRecorder {
    private let engine = AVAudioEngine()
    private(set) var sampleRate: Double = 48_000
    private var samples: [Float] = []
    private let lock = NSLock()
    private var running = false

    var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AutoSyncError.micUnavailable("no default input")
        }
        sampleRate = format.sampleRate
        samples.removeAll(keepingCapacity: true)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let ch = Int(buffer.format.channelCount)
            self.lock.lock()
            if ch == 1 {
                self.samples.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: n))
            } else {
                let l = channels[0]
                let r = ch > 1 ? channels[1] : channels[0]
                for i in 0..<n {
                    self.samples.append(0.5 * (l[i] + r[i]))
                }
            }
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

/// Drives Engine measure mode + mic correlation for a one-shot Autosync pass.
enum AutoSyncRunner {
    static let chirpDuration: Double = 0.12
    static let settleSeconds: Double = 0.18
    static let listenSeconds: Double = 0.9 // covers maxDelayMs + margin
    static let probeGain: Float = 1.0
    static let retryGain: Float = 1.4
    static let maxAttemptsPerDevice = 2

    @MainActor
    static func requestMicAccess() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Measure relative delays for `devices`. Calls `onProgress` with the device currently probing.
    @MainActor
    static func run(
        engine: Engine,
        devices: [AudioDevice],
        onProgress: (String) -> Void
    ) async throws -> [String: Float] {
        guard engine.running else { throw AutoSyncError.notRunning }
        guard devices.count >= 2 else { throw AutoSyncError.needTwoDevices }

        let granted = await requestMicAccess()
        guard granted else { throw AutoSyncError.micDenied }

        let chirp = makeChirp(sampleRate: engine.sampleRate, durationSeconds: chirpDuration)
        let recorder = MicRecorder()
        do {
            try recorder.start()
        } catch let e as AutoSyncError {
            throw e
        } catch {
            throw AutoSyncError.micUnavailable(error.localizedDescription)
        }

        engine.beginLatencyMeasure(chirp: chirp)
        defer {
            recorder.stop()
            if engine.isMeasuring { engine.endLatencyMeasure() }
        }

        try await sleep(0.25)

        var arrivals: [String: Float] = [:]

        for device in devices {
            onProgress(device.name)
            var lastError: AutoSyncError = .lowConfidence(device: device.name)
            var measured: Float?

            for attempt in 0..<maxAttemptsPerDevice {
                let gain = attempt == 0 ? probeGain : retryGain
                do {
                    measured = try await measureArrival(
                        engine: engine,
                        recorder: recorder,
                        chirp: chirp,
                        deviceUid: device.uid,
                        deviceName: device.name,
                        gain: gain
                    )
                    break
                } catch let e as AutoSyncError {
                    lastError = e
                }
            }

            guard let arrival = measured else { throw lastError }
            arrivals[device.uid] = arrival
        }

        engine.endLatencyMeasure()
        return relativeDelaysMs(arrivals: arrivals, maxMs: Float(Engine.maxDelayMs))
    }

    @MainActor
    private static func measureArrival(
        engine: Engine,
        recorder: MicRecorder,
        chirp: [Float],
        deviceUid: String,
        deviceName: String,
        gain: Float
    ) async throws -> Float {
        engine.soloForMeasure(uid: deviceUid, gain: gain)
        try await sleep(settleSeconds)

        let mark = recorder.sampleCount
        engine.scheduleProbe()
        try await sleep(chirpDuration + listenSeconds)

        var spins = 0
        while !engine.isProbeIdle && spins < 50 {
            try await sleep(0.02)
            spins += 1
        }
        // Extra tail so late Bluetooth packets still land in the window.
        try await sleep(0.05)

        let all = recorder.snapshot()
        let micRate = recorder.sampleRate
        let pad = Int(0.06 * micRate)
        let start = max(0, mark - pad)
        let end = min(all.count, mark + Int((chirpDuration + listenSeconds + 0.08) * micRate))
        guard end > start + chirp.count / 2 else {
            throw AutoSyncError.lowConfidence(device: deviceName)
        }

        let window = removeDC(Array(all[start..<end]))
        let ref = resampleLinear(chirp, from: engine.sampleRate, to: micRate)

        guard let est = estimateDelayMs(reference: ref, recorded: window, sampleRate: micRate) else {
            throw AutoSyncError.lowConfidence(device: deviceName)
        }
        guard est.confidence >= latencyMinConfidence,
              est.peakScore >= latencyMinPeakScore else {
            throw AutoSyncError.lowConfidence(device: deviceName)
        }

        let markInWindow = Float(mark - start) * 1000 / Float(micRate)
        return est.delayMs - markInWindow
    }

    private static func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
