import XCTest
@testable import SoundStageCore

final class LatencyMeasureTests: XCTestCase {
    func testMakeChirpLength() {
        let sr = 48_000.0
        let chirp = makeChirp(sampleRate: sr, durationSeconds: 0.12)
        XCTAssertEqual(chirp.count, 5_760)
        XCTAssertGreaterThan(chirp.map { abs($0) }.max() ?? 0, 0.1)
        XCTAssertLessThan(abs(chirp.first!), 0.05)
        XCTAssertLessThan(abs(chirp.last!), 0.05)
    }

    func testEstimateKnownLagNearestMs() {
        let sr = 48_000.0
        let chirp = makeChirp(sampleRate: sr, durationSeconds: 0.1)
        let lagSamples = 9_600 // 200.0 ms
        var recorded = [Float](repeating: 0, count: lagSamples + chirp.count + 4_000)
        for i in 0..<chirp.count {
            recorded[lagSamples + i] = chirp[i] * 0.7
        }
        for i in 0..<recorded.count where abs(recorded[i]) < 1e-8 {
            recorded[i] = Float.random(in: -0.008...0.008)
        }

        let est = estimateDelayMs(reference: chirp, recorded: recorded, sampleRate: sr)
        XCTAssertNotNil(est)
        XCTAssertEqual(est!.delayMs, 200, accuracy: 0.5)
        XCTAssertEqual(nearestMs(est!.delayMs), 200, accuracy: 0)
        XCTAssertGreaterThan(est!.confidence, latencyMinConfidence)
        XCTAssertGreaterThan(est!.peakScore, latencyMinPeakScore)
    }

    func testEstimateFractionalLagInterpolates() {
        let sr = 48_000.0
        let chirp = makeChirp(sampleRate: sr, durationSeconds: 0.08)
        // 123.5 ms → 5928 samples.
        let lagSamples = 5_928
        var recorded = [Float](repeating: 0, count: lagSamples + chirp.count + 3_000)
        for i in 0..<chirp.count {
            recorded[lagSamples + i] = chirp[i]
        }
        let est = estimateDelayMs(reference: chirp, recorded: recorded, sampleRate: sr)!
        let expected = Float(Double(lagSamples) * 1000.0 / sr) // 123.5
        XCTAssertEqual(est.delayMs, expected, accuracy: 0.5)
        // Nearest-ms quantization should land on 123 or 124 depending on interp.
        let q = nearestMs(est.delayMs)
        XCTAssertTrue(q == 123 || q == 124, "got \(q)")
    }

    func testPrefersEarlierArrivalOverLouderReflection() {
        let sr = 48_000.0
        let chirp = makeChirp(sampleRate: sr, durationSeconds: 0.08)
        let direct = 4_800   // 100 ms
        let reflect = 7_200  // 150 ms, louder
        var recorded = [Float](repeating: 0, count: reflect + chirp.count + 2_000)
        for i in 0..<chirp.count {
            recorded[direct + i] += chirp[i] * 0.6
            recorded[reflect + i] += chirp[i] * 1.0
        }
        let est = estimateDelayMs(reference: chirp, recorded: recorded, sampleRate: sr)!
        // Should lock onto the nearer (earlier) path, not the louder reflection.
        XCTAssertEqual(est.delayMs, 100, accuracy: 2)
    }

    func testEstimateRejectsEmpty() {
        XCTAssertNil(estimateDelayMs(reference: [], recorded: [0, 1], sampleRate: 48_000))
        XCTAssertNil(estimateDelayMs(reference: [1, 2, 3], recorded: [1], sampleRate: 48_000))
    }

    func testEstimateRejectsPureNoise() {
        let sr = 48_000.0
        let chirp = makeChirp(sampleRate: sr, durationSeconds: 0.05)
        let noise = (0..<chirp.count + 8_000).map { _ in Float.random(in: -0.2...0.2) }
        let est = estimateDelayMs(reference: chirp, recorded: noise, sampleRate: sr)
        if let est {
            XCTAssertTrue(
                est.confidence < latencyMinConfidence || est.peakScore < latencyMinPeakScore,
                "noise-only should fail confidence/peak gates"
            )
        }
    }

    func testInterpolatePeakLagCenter() {
        let scores: [Float] = [0.1, 0.5, 1.0, 0.5, 0.1]
        XCTAssertEqual(interpolatePeakLag(scores: scores, peak: 2), 2.0, accuracy: 1e-6)
    }

    func testInterpolatePeakLagOffset() {
        // Peak slightly toward the right neighbor.
        let scores: [Float] = [0.0, 0.4, 1.0, 0.8, 0.0]
        let lag = interpolatePeakLag(scores: scores, peak: 2)
        XCTAssertGreaterThan(lag, 2.0)
        XCTAssertLessThan(lag, 2.5)
    }

    func testNearestMs() {
        XCTAssertEqual(nearestMs(180.4), 180)
        XCTAssertEqual(nearestMs(180.5), 181)
        XCTAssertEqual(nearestMs(180.6), 181)
        XCTAssertEqual(nearestMs(12.49), 12)
        XCTAssertEqual(nearestMs(12.5), 13)
    }

    func testRelativeDelaysSlowestIsZeroNearestMs() {
        let delays = relativeDelaysMs(
            arrivals: ["bt": 220.4, "builtin": 12.2, "hdmi": 18.8],
            maxMs: 750
        )
        XCTAssertEqual(delays["bt"]!, 0)
        XCTAssertEqual(delays["builtin"]!, 208) // 220.4 - 12.2 = 208.2 → 208
        XCTAssertEqual(delays["hdmi"]!, 202)    // 220.4 - 18.8 = 201.6 → 202
    }

    func testRelativeDelaysClamped() {
        let delays = relativeDelaysMs(
            arrivals: ["slow": 900, "fast": 0],
            maxMs: 750
        )
        XCTAssertEqual(delays["fast"]!, 750)
        XCTAssertEqual(delays["slow"]!, 0)
    }

    func testResampleLinearIdentity() {
        let x: [Float] = [0, 1, 0, -1, 0]
        XCTAssertEqual(resampleLinear(x, from: 48_000, to: 48_000), x)
    }

    func testResampleLinearUpsampleLength() {
        let x: [Float] = [0, 1, 0]
        let y = resampleLinear(x, from: 24_000, to: 48_000)
        XCTAssertEqual(y.count, 6)
    }

    func testRemoveDCBlocksOffset() {
        let x = [Float](repeating: 0.3, count: 8_000)
        let y = removeDC(x)
        let tail = y.suffix(4_000)
        let mean = tail.reduce(0, +) / Float(tail.count)
        XCTAssertLessThan(abs(mean), 0.02)
    }
}
