import Foundation

/// Result of locating a probe in a microphone recording.
public struct DelayEstimate: Equatable {
    /// Lag from the start of `recorded` to the start of the matched probe, in ms
    /// (sub-sample interpolated; not yet quantized).
    public let delayMs: Float
    /// Peak correlation strength vs off-peak energy. Below `latencyMinConfidence` is unreliable.
    public let confidence: Float
    /// Raw normalized correlation at the chosen peak (≈1.0 is a perfect match).
    public let peakScore: Float

    public init(delayMs: Float, confidence: Float, peakScore: Float = 0) {
        self.delayMs = delayMs
        self.confidence = confidence
        self.peakScore = peakScore
    }
}

/// Minimum confidence accepted by Autosync.
public let latencyMinConfidence: Float = 1.8

/// Minimum normalized correlation at the chosen peak.
public let latencyMinPeakScore: Float = 0.25

/// Fraction of the global max correlation used to accept an earlier “first arrival” peak.
public let latencyFirstArrivalFraction: Float = 0.55

/// Exponential sine sweep (chirp), mono, amplitude tapered at both ends.
public func makeChirp(
    sampleRate: Double,
    durationSeconds: Double = 0.12,
    f0: Double = 500,
    f1: Double = 5000,
    amplitude: Float = 0.5
) -> [Float] {
    let n = max(1, Int((sampleRate * durationSeconds).rounded()))
    guard n > 1 else { return [0] }
    let sr = sampleRate
    let t1 = Double(n - 1) / sr
    guard f0 > 0, f1 > f0, t1 > 0 else { return [Float](repeating: 0, count: n) }
    let k = pow(f1 / f0, 1.0 / t1)
    let logK = log(k)
    var out = [Float](repeating: 0, count: n)
    let fade = max(1, n / 20)
    for i in 0..<n {
        let t = Double(i) / sr
        let phase = 2.0 * Double.pi * f0 * (pow(k, t) - 1.0) / logK
        var env: Float = amplitude
        if i < fade {
            env *= Float(i) / Float(fade)
        } else if i >= n - fade {
            env *= Float(n - 1 - i) / Float(fade)
        }
        out[i] = env * Float(sin(phase))
    }
    return out
}

/// Linear resample of a mono buffer (used when mic rate ≠ engine rate).
public func resampleLinear(_ input: [Float], from: Double, to: Double) -> [Float] {
    guard !input.isEmpty, from > 0, to > 0 else { return input }
    if abs(from - to) < 0.5 { return input }
    let outCount = max(1, Int((Double(input.count) * to / from).rounded()))
    if outCount == 1 { return [input[0]] }
    var out = [Float](repeating: 0, count: outCount)
    let scale = Double(input.count - 1) / Double(outCount - 1)
    for i in 0..<outCount {
        let src = Double(i) * scale
        let i0 = Int(src)
        let i1 = min(input.count - 1, i0 + 1)
        let t = Float(src - Double(i0))
        out[i] = input[i0] * (1 - t) + input[i1] * t
    }
    return out
}

/// Simple one-pole DC / rumble blocker for mic captures.
public func removeDC(_ input: [Float], coeff: Float = 0.995) -> [Float] {
    guard !input.isEmpty else { return input }
    var out = [Float](repeating: 0, count: input.count)
    var prevX: Float = 0
    var prevY: Float = 0
    for i in 0..<input.count {
        let x = input[i]
        let y = x - prevX + coeff * prevY
        out[i] = y
        prevX = x
        prevY = y
    }
    return out
}

/// Parabolic interpolation around an integer peak index → fractional lag.
public func interpolatePeakLag(scores: [Float], peak: Int) -> Double {
    guard peak > 0, peak + 1 < scores.count else { return Double(peak) }
    let y0 = Double(scores[peak - 1])
    let y1 = Double(scores[peak])
    let y2 = Double(scores[peak + 1])
    let denom = y0 - 2 * y1 + y2
    guard abs(denom) > 1e-12 else { return Double(peak) }
    let delta = 0.5 * (y0 - y2) / denom
    return Double(peak) + max(-0.5, min(0.5, delta))
}

/// Round a millisecond value to the nearest whole ms.
public func nearestMs(_ ms: Float) -> Float {
    ms.rounded()
}

/// Cross-correlate `recorded` against `reference` and return the lag of the
/// earliest strong peak (direct path), with sub-sample interpolation.
public func estimateDelayMs(
    reference: [Float],
    recorded: [Float],
    sampleRate: Double
) -> DelayEstimate? {
    let refLen = reference.count
    let recLen = recorded.count
    guard refLen > 8, recLen > refLen, sampleRate > 0 else { return nil }

    var refEnergy: Float = 0
    for x in reference { refEnergy += x * x }
    guard refEnergy > 1e-12 else { return nil }

    let maxLag = recLen - refLen
    var scores = [Float](repeating: 0, count: maxLag + 1)

    for lag in 0...maxLag {
        var sum: Float = 0
        var recEnergy: Float = 0
        for i in 0..<refLen {
            let r = recorded[lag + i]
            sum += reference[i] * r
            recEnergy += r * r
        }
        let denom = sqrt(refEnergy * max(recEnergy, 1e-12))
        scores[lag] = sum / denom
    }

    var globalBestLag = 0
    var globalBest: Float = -.greatestFiniteMagnitude
    for lag in 0...maxLag where scores[lag] > globalBest {
        globalBest = scores[lag]
        globalBestLag = lag
    }
    guard globalBest >= latencyMinPeakScore * 0.5 else { return nil }

    // Prefer the earliest peak that reaches a solid fraction of the global max —
    // that tracks the direct path (“nearest sound”) instead of a louder reflection.
    let threshold = max(globalBest * latencyFirstArrivalFraction, latencyMinPeakScore)
    let lobe = max(1, refLen / 8)
    var chosenLag = globalBestLag
    var chosenScore = globalBest
    var lag = 0
    while lag <= maxLag {
        if scores[lag] >= threshold {
            // Local maximum in a small neighborhood.
            let lo = max(0, lag - 2)
            let hi = min(maxLag, lag + 2)
            var localBest = lag
            var localScore = scores[lag]
            for j in lo...hi where scores[j] > localScore {
                localScore = scores[j]
                localBest = j
            }
            if localScore >= threshold {
                chosenLag = localBest
                chosenScore = localScore
                break
            }
            lag = localBest + lobe
        } else {
            lag += 1
        }
    }

    // Runner-up outside the main lobe → confidence.
    let exclude = max(lobe, refLen / 4)
    var secondScore: Float = 0
    for i in 0...maxLag {
        if abs(i - chosenLag) <= exclude { continue }
        if scores[i] > secondScore { secondScore = scores[i] }
    }
    let ratio = chosenScore / max(secondScore, 0.05)
    let confidence = max(chosenScore * 3, ratio)

    let fracLag = interpolatePeakLag(scores: scores, peak: chosenLag)
    let delayMs = Float(fracLag * 1000.0 / sampleRate)
    return DelayEstimate(delayMs: delayMs, confidence: confidence, peakScore: chosenScore)
}

/// Convert absolute arrival times into relative delays (slowest device → 0 ms),
/// quantized to the nearest millisecond.
public func relativeDelaysMs(
    arrivals: [String: Float],
    maxMs: Float
) -> [String: Float] {
    guard let slowest = arrivals.values.max() else { return [:] }
    var out: [String: Float] = [:]
    for (uid, arrival) in arrivals {
        let d = nearestMs(slowest - arrival)
        out[uid] = max(0, min(maxMs, d))
    }
    return out
}
