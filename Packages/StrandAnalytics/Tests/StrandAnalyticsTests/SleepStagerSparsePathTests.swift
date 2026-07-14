import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// Sparse-path coverage for the four SleepStager borrow-signals changes (V1 stager, WHOOP-5 / RR-only
/// nights). Each change is behind a gate that is INERT on a dense WHOOP-4.0 night, so the frozen dense
/// goldens stay byte-identical; these tests exercise the gate's ACTIVE side directly and pin the new
/// constants. Nothing here re-freezes or edits a dense golden.
final class SleepStagerSparsePathTests: XCTestCase {

    // MARK: - fixtures (self-contained; no dependency on the frozen SleepStagerTests helpers)

    /// A dead-flat gravity stream (constant orientation, Δ ≡ 0 — a strap set on a surface, or a synthetic
    /// still night) at one sample every `everyS` seconds.
    private func flatGravity(start: Int, durationS: Int, everyS: Int = 1) -> [GravitySample] {
        stride(from: 0, to: durationS, by: everyS).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1.0) }
    }
    /// A WORN-still gravity stream: tiny micro-motion (|Δ| ≈ 0.005 g) — above the dead-flat off-wrist floor
    /// but below the stillness threshold, so it is "still" yet never reads off-wrist.
    private func micromotionGravity(start: Int, durationS: Int) -> [GravitySample] {
        (0..<durationS).map { GravitySample(ts: start + $0, x: 0, y: 0, z: ($0 % 2 == 0) ? 1.0 : 1.005) }
    }
    private func hrStream(start: Int, durationS: Int, bpm: Int = 50, everyS: Int = 1) -> [HRSample] {
        stride(from: 0, to: durationS, by: everyS).map { HRSample(ts: start + $0, bpm: bpm) }
    }
    /// A ~1 Hz R-R stream (steady ~1000 ms beats) with a `breathHz` respiratory-sinus-arrhythmia modulation.
    private func rsaRR(start: Int, durationS: Int, breathHz: Double = 0.25, ampMs: Double = 40.0) -> [RRInterval] {
        var rows: [RRInterval] = []
        var tSec = 0.0
        while tSec < Double(durationS) {
            let rrMs = 1000.0 + ampMs * sin(2.0 * Double.pi * breathHz * tSec)
            tSec += rrMs / 1000.0
            rows.append(RRInterval(ts: start + Int(tSec), rrMs: Int(rrMs)))
        }
        return rows
    }
    /// Unix seconds at local (tz=0) hour `h` on a fixed reference day, so a window's center lands where we
    /// want relative to the daytime band [11, 20).
    private func hourUTC(_ h: Int, day: Int = 20_000) -> Int { day * 86_400 + h * 3_600 }

    // MARK: - change 1: RR-RSA into the resp-absent REM path

    /// The per-window RSA helper recovers a planted breathing rate AND a finite RRV from an R-R window, with
    /// NO plausible-band clamp — the resp-absent substitute for `respRateAndRRV`.
    func testRsaRateAndRRVRecoversPlantedBreathing_change1() {
        let rows = rsaRR(start: 1_700_000_000, durationS: 300)   // ~5 min, 0.25 Hz = 15 br/min
        let (rate, rrv) = SleepStager.rsaRateAndRRV(rows.map { Double($0.rrMs) })
        XCTAssertTrue(rate.isFinite, "expected a finite RSA rate, got \(rate)")
        XCTAssertEqual(rate, 15.0, accuracy: 4.0, "RSA peak-pick should land near the planted 15 br/min")
        XCTAssertTrue(rrv.isFinite && rrv >= 0, "RRV must be a finite, non-negative std of breath intervals")
    }

    func testRsaRateAndRRVTooFewBeatsIsNaN_change1() {
        let (rate, rrv) = SleepStager.rsaRateAndRRV([1000, 1010, 990])
        XCTAssertTrue(rate.isNaN); XCTAssertTrue(rrv.isNaN)
    }

    /// End-to-end wiring: on a resp-ABSENT but R-R-PRESENT night the funnel now sees a usable respiration
    /// signal (RSA-derived), where the same night with NO R-R still reports the resp channel absent. Proves
    /// `extractFeatures` engages the RR-RSA fallback only when the resp segment is genuinely empty.
    func testRespAbsentRRPresentNightRecoversRespSignal_change1() {
        let start = 1_700_100_000
        let dur = 90 * 60
        let grav = flatGravity(start: start, durationS: dur)
        let hr = hrStream(start: start, durationS: dur, bpm: 50)
        let rr = rsaRR(start: start, durationS: dur)

        let withRR = SleepStager.remFunnelDiagnostic(start: start, end: start + dur,
                                                     grav: grav, hr: hr, rr: rr, resp: [])
        XCTAssertNotNil(withRR)
        XCTAssertTrue(withRR!.respChannelPresent,
                      "RR-RSA must supply an irregular-respiration signal on a resp-absent, RR-present night")

        // Control: no R-R either → nothing to derive from → resp channel stays absent (unchanged).
        let noRR = SleepStager.remFunnelDiagnostic(start: start, end: start + dur,
                                                   grav: grav, hr: hr, rr: [], resp: [])
        XCTAssertNotNil(noRR)
        XCTAssertFalse(noRR!.respChannelPresent,
                       "with neither resp nor R-R the channel is genuinely absent (no fabricated signal)")
    }

    // MARK: - change 2: session HF power into the sparse-cardiac DEEP verdict

    /// A depth-signature epoch (still, low HR, regular breathing) with a MISSING per-epoch RMSSD.
    private func depthEpoch() -> SleepStager.EpochFeatures {
        SleepStager.EpochFeatures(index: 0, midTs: 0, count: 0, moveFrac: 0, ckSleep: true,
                                  hr: 50, hrVar: 0, rmssd: .nan, sdnn: 0, respRate: 14, rrv: .nan, clock: 0.5)
    }

    func testSessionHFStrengthensDeepOnSparsePath_change2() {
        let bars = (hrLo: 55.0, hrHi: 90.0, rmssdHi: 50.0, hrvarHi: 100.0, rrvHi: 1.0, rrvLo: 0.5)
        func classify(cardiacSparse: Bool, hf: Double) -> String {
            SleepStager.classifyOne(depthEpoch(), hrLo: bars.hrLo, hrHi: bars.hrHi, rmssdHi: bars.rmssdHi,
                                    hrvarHi: bars.hrvarHi, rrvHi: bars.rrvHi, rrvLo: bars.rrvLo,
                                    cardiacSparse: cardiacSparse, hf: hf, hfBar: SleepStager.hfDeepMinPowerMs2)
        }
        // Dense path (cardiacSparse false): HF is IGNORED — a missing RMSSD stays pro-deep (#127 unchanged).
        XCTAssertEqual(classify(cardiacSparse: false, hf: 5.0), "deep",
                       "dense path must be byte-identical: missing RMSSD is pro-deep regardless of HF")
        // Sparse path + adequate HF power → the parasympathetic bar is cleared → deep.
        XCTAssertEqual(classify(cardiacSparse: true, hf: 300.0), "deep",
                       "sparse night with real vagal HF power should be allowed deep")
        // Sparse path + weak HF power → parasympathetic bar unmet → NOT deep (falls to light).
        XCTAssertNotEqual(classify(cardiacSparse: true, hf: 10.0), "deep",
                          "sparse night with negligible HF power must not be over-called deep")
        // Sparse path + HF unavailable (NaN) → falls back to the blanket pro-deep rule (no regression).
        XCTAssertEqual(classify(cardiacSparse: true, hf: .nan), "deep",
                       "with no HF reading the sparse path keeps the existing pro-deep fallback")
    }

    /// The REM/deep reject-reason mirror must move in lockstep with classifyOne: on the sparse path a
    /// weak-HF depth epoch no longer wins deep, so it is attributed to a REM precondition, not `wonOtherStage`.
    func testRemRejectReasonMirrorsHFDeepGate_change2() {
        let bars = (hrLo: 55.0, hrHi: 90.0, rmssdHi: 50.0, hrvarHi: 100.0, rrvHi: 1.0, rrvLo: 0.5)
        func reason(cardiacSparse: Bool, hf: Double) -> SleepStager.REMRejectReason {
            SleepStager.remRejectReason(depthEpoch(), hrLo: bars.hrLo, hrHi: bars.hrHi, rmssdHi: bars.rmssdHi,
                                        hrvarHi: bars.hrvarHi, rrvHi: bars.rrvHi, rrvLo: bars.rrvLo,
                                        cardiacSparse: cardiacSparse, hf: hf, hfBar: SleepStager.hfDeepMinPowerMs2)
        }
        // High HF on the sparse path → wins deep → not a REM candidate.
        XCTAssertEqual(reason(cardiacSparse: true, hf: 300.0), .wonOtherStage)
        // Weak HF on the sparse path → no longer deep → attributed to a REM precondition (no cardiac activation).
        XCTAssertEqual(reason(cardiacSparse: true, hf: 10.0), .noCardiacActivation)
    }

    // MARK: - change 3: gravity dead-flat off-wrist proxy (sparse/absent-HR only)

    func testGravityOffWristProxyInertOnDenseHR_change3() {
        let p = SleepStager.Period(stage: "sleep", start: 0, end: 90 * 60)
        let grav = flatGravity(start: 0, durationS: 90 * 60)          // dead flat
        let deltas = SleepStager.gravityDeltas(grav)
        let dense = hrStream(start: 0, durationS: 90 * 60, bpm: 50)   // 1 Hz dense HR
        XCTAssertTrue(SleepStager.offWristGravitySpans(p, grav: grav, deltas: deltas, hr: dense).isEmpty,
                      "dense HR → the HR-gap proxy owns the backstop; the gravity proxy must stay inert")
        XCTAssertEqual(SleepStager.offWristFraction(p, hr: dense, wristOff: [], grav: grav, deltas: deltas),
                       0.0, accuracy: 1e-9, "a dead-flat dense-HR night must read 0% off-wrist (byte-identical)")
    }

    func testGravityOffWristProxyFiresOnSparseOrAbsentHR_change3() {
        let p = SleepStager.Period(stage: "sleep", start: 0, end: 90 * 60)
        let grav = flatGravity(start: 0, durationS: 90 * 60)
        let deltas = SleepStager.gravityDeltas(grav)

        // Absent HR: the HR-gap proxy can't assert off-wrist, but dead-flat gravity for ≥20 min can.
        let absentSpans = SleepStager.offWristGravitySpans(p, grav: grav, deltas: deltas, hr: [])
        XCTAssertEqual(absentSpans.count, 1, "dead-flat gravity with no HR must register one off-wrist span")
        XCTAssertGreaterThan(
            SleepStager.offWristFraction(p, hr: [], wristOff: [], grav: grav, deltas: deltas), 0.9,
            "a whole dead-flat, HR-less run reads as almost entirely off-wrist")

        // Sparse HR (4 samples / 90 min → density gate disables the HR-gap proxy): gravity proxy engages.
        let sparse = [0, 1_500, 3_000, 4_500].map { HRSample(ts: $0, bpm: 50) }
        XCTAssertFalse(SleepStager.offWristGravitySpans(p, grav: grav, deltas: deltas, hr: sparse).isEmpty,
                       "sparse HR (HR-gap proxy disabled) is exactly where the gravity proxy must engage")
    }

    func testWornMicromotionIsNotFlaggedOffWrist_change3() {
        let p = SleepStager.Period(stage: "sleep", start: 0, end: 90 * 60)
        let grav = micromotionGravity(start: 0, durationS: 90 * 60)   // |Δ| ≈ 0.005 g > flat floor
        let deltas = SleepStager.gravityDeltas(grav)
        XCTAssertTrue(SleepStager.offWristGravitySpans(p, grav: grav, deltas: deltas, hr: []).isEmpty,
                      "a worn but still wrist keeps micro-motion above the dead-flat floor → not off-wrist")
    }

    // MARK: - change 4: flag-not-drop the over-long (>16 h) run

    func testOverLongRunIsFlaggedNotDropped_change4() {
        let start = hourUTC(22)                       // 22:00 local → a 17 h span centers overnight
        let dur = 17 * 60 * 60                        // > maxMainSleepSpanS (16 h)
        // Dead-flat gravity keeps it ONE still run; DENSE HR keeps the gravity off-wrist proxy inert so the
        // night is not dropped for a different reason, and confirms the low sleep-band HR.
        let grav = flatGravity(start: start, durationS: dur, everyS: 2)
        let hr = hrStream(start: start, durationS: dur, bpm: 50, everyS: 10)

        let sessions = SleepStager.detectSleep(hr: hr, gravity: grav)
        XCTAssertEqual(sessions.count, 1, "an over-long run is now RETAINED, not dropped (flag-not-drop)")
        let s = sessions[0]
        XCTAssertTrue(s.lowConfidence, "the >16 h run must be marked low-confidence")
        XCTAssertGreaterThan(s.end - s.start, 16 * 60 * 60, "the retained span exceeds the physiological cap")
        XCTAssertFalse(s.stages.isEmpty, "the retained run is still staged")
    }

    func testNormalNightIsNotFlagged_change4() {
        let start = hourUTC(22)
        let dur = 8 * 60 * 60                         // within the cap
        let grav = flatGravity(start: start, durationS: dur, everyS: 2)
        let hr = hrStream(start: start, durationS: dur, bpm: 50, everyS: 10)
        let sessions = SleepStager.detectSleep(hr: hr, gravity: grav)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertFalse(sessions[0].lowConfidence, "an ordinary night must never carry the low-confidence flag")
    }

    // MARK: - pinned constants

    func testNewConstantsPinned() {
        XCTAssertEqual(SleepStager.offWristGravityFlatG, 0.001, accuracy: 0.0,
                       "off-wrist dead-flat floor is one order of magnitude below the 0.01 stillness threshold")
        XCTAssertLessThan(SleepStager.offWristGravityFlatG, SleepStager.gravityStillThresholdG,
                          "the off-wrist flat floor must be strictly below the stillness threshold")
        XCTAssertEqual(SleepStager.hfDeepMinPowerMs2, 100.0, accuracy: 0.0,
                       "session HF pro-deep floor (ms^2) on the sparse-cardiac path")
    }
}
