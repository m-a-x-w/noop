import XCTest
import WhoopStore
import WhoopProtocol
@testable import StrandImport

/// THE round-trip contract for the TCX writer: serialize with TcxExporter, re-parse with the REAL
/// TcxParser, assert field-level equality. Mirrors WhoopCsvExporterTests so any structural drift
/// fails a test rather than silently producing a file Strava / intervals.icu (or NOOP itself)
/// can't read. `@testable` because TcxParser is internal.
final class TcxExporterTests: XCTestCase {

    // 2026-06-01T08:00:00Z (1_780_272_000 is 2026-06-01 00:00Z, pinned by WhoopCsvExporterTests).
    private let start = 1_780_272_000 + 8 * 3600

    private func row(sport: String = "Running", durationS: Double? = 3600,
                     energyKcal: Double? = 712.4, avgHr: Int? = 152, maxHr: Int? = 178,
                     distanceM: Double? = 10_400, notes: String? = nil) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + 3600, sport: sport, source: "whoop",
                   durationS: durationS, energyKcal: energyKcal, avgHr: avgHr, maxHr: maxHr,
                   strain: 14.2, distanceM: distanceM, zonesJSON: nil, notes: notes)
    }

    func testRoundTripThroughRealParser() throws {
        // One HR sample per minute, 100→160 bpm — mean exactly 130.
        let hr = (0...60).map { HRSample(ts: start + $0 * 60, bpm: 100 + $0) }
        let xml = TcxExporter.tcx(row(), hr: hr)

        // The times the writer emits are ISO-8601 UTC with a trailing Z.
        XCTAssertTrue(xml.contains("<Id>2026-06-01T08:00:00Z</Id>"))
        XCTAssertTrue(xml.contains("<Lap StartTime=\"2026-06-01T08:00:00Z\">"))
        XCTAssertTrue(xml.contains("<Activity Sport=\"Running\">"))

        let r = TcxParser.parse(data: Data(xml.utf8))
        let a = try XCTUnwrap(r.activity)
        XCTAssertEqual(a.kind, .tcx)
        XCTAssertEqual(a.sport, "Running")
        XCTAssertEqual(a.start, Date(timeIntervalSince1970: TimeInterval(start)))
        XCTAssertEqual(a.end, Date(timeIntervalSince1970: TimeInterval(start + 3600)))
        XCTAssertEqual(a.durationS, 3600)
        XCTAssertEqual(a.hrSampleCount, 61)
        XCTAssertEqual(a.avgHr, 130)               // parser computes the mean from the track
        XCTAssertEqual(a.maxHr, 178)               // the Lap's stated MaximumHeartRateBpm wins
        XCTAssertEqual(a.distanceM, 10_400)        // Lap summary — the track carries no coordinates
        XCTAssertEqual(a.energyKcal, 712)          // Calories is an integer element, rounded
        XCTAssertEqual(a.gpsPointCount, 0)
        XCTAssertEqual(r.skipped, 0)
    }

    func testSportMapsToRestrictedEnumAndRealLabelRidesInNotes() {
        XCTAssertEqual(TcxExporter.schemaSport("Running"), "Running")
        XCTAssertEqual(TcxExporter.schemaSport("trail_running"), "Running")
        XCTAssertEqual(TcxExporter.schemaSport("Cycling"), "Biking")
        XCTAssertEqual(TcxExporter.schemaSport("Ride"), "Biking")
        XCTAssertEqual(TcxExporter.schemaSport("BIKE"), "Biking")
        XCTAssertEqual(TcxExporter.schemaSport("Strength Training"), "Other")

        // The real free-text sport survives in <Notes>, XML-escaped, with the row's own notes and
        // provenance alongside.
        let xml = TcxExporter.tcx(row(sport: "Rowing <2k & \"test\">", notes: "easy session"), hr: [])
        XCTAssertTrue(xml.contains("<Activity Sport=\"Other\">"))
        XCTAssertTrue(xml.contains("Rowing &lt;2k &amp; &quot;test&quot;&gt;"))
        XCTAssertTrue(xml.contains("easy session"))
        XCTAssertTrue(xml.contains("exported by NOOP"))
    }

    func testEmptyHrWindowStillProducesValidSummaryOnlyTcx() {
        let xml = TcxExporter.tcx(row(durationS: 1800, energyKcal: 300), hr: [])
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>1800</TotalTimeSeconds>"))
        XCTAssertTrue(xml.contains("<Calories>300</Calories>"))
        XCTAssertTrue(xml.contains("<AverageHeartRateBpm><Value>152</Value></AverageHeartRateBpm>"))
        // The real parser must accept the document without flagging anything skipped. With zero
        // trackpoints there's no honest interval, so it yields no activity — the summary-only file
        // is for third-party consumers (Strava accepts an empty Track); NOOP's own lossless
        // round-trip path stays the WHOOP-CSV zip.
        let r = TcxParser.parse(data: Data(xml.utf8))
        XCTAssertNil(r.activity)
        XCTAssertEqual(r.kind, .tcx)
        XCTAssertEqual(r.skipped, 0)
    }

    func testNonPositiveBpmSamplesAreDropped() throws {
        let hr = [HRSample(ts: start, bpm: 0), HRSample(ts: start + 60, bpm: -5),
                  HRSample(ts: start + 120, bpm: 140), HRSample(ts: start + 180, bpm: 150)]
        let xml = TcxExporter.tcx(row(), hr: hr)
        let a = try XCTUnwrap(TcxParser.parse(data: Data(xml.utf8)).activity)
        XCTAssertEqual(a.hrSampleCount, 2)
    }

    func testDurationFallsBackToWindowWhenRowHasNone() {
        let xml = TcxExporter.tcx(row(durationS: nil), hr: [])
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>3600</TotalTimeSeconds>"))
    }

    func testRequiredLapFieldsDefaultToZeroOptionalHrOmitted() {
        // DistanceMeters + Calories are REQUIRED in ActivityLap_t → emitted as 0 when the row carried
        // nothing (never omitted, or strict consumers reject the file). Average/MaximumHeartRateBpm
        // ARE optional in the schema, so those stay omitted rather than faked to 0.
        let xml = TcxExporter.tcx(row(energyKcal: nil, avgHr: nil, maxHr: nil, distanceM: nil), hr: [])
        XCTAssertTrue(xml.contains("<DistanceMeters>0</DistanceMeters>"))
        XCTAssertTrue(xml.contains("<Calories>0</Calories>"))
        XCTAssertFalse(xml.contains("<AverageHeartRateBpm>"))
        XCTAssertFalse(xml.contains("<MaximumHeartRateBpm>"))
    }

    func testEmptyHrWindowOmitsTrackElementEntirely() {
        // An empty <Track></Track> violates Track_t (Trackpoint minOccurs=1); the writer omits the
        // element instead. The Lap (with Track minOccurs=0) stays schema-valid.
        let xml = TcxExporter.tcx(row(), hr: [])
        XCTAssertFalse(xml.contains("<Track>"))
        XCTAssertFalse(xml.contains("<Trackpoint>"))
    }

    func testHeartRateValuesClampToSchemaPositiveByte() throws {
        // HeartRateInBeatsPerMinute_t/Value is positiveByte (1–255). A corrupt importer maxHr of 999
        // must clamp, not emit an out-of-domain value.
        let hr = [HRSample(ts: start, bpm: 300), HRSample(ts: start + 60, bpm: 140)]
        let xml = TcxExporter.tcx(row(maxHr: 999), hr: hr)
        XCTAssertTrue(xml.contains("<MaximumHeartRateBpm><Value>255</Value></MaximumHeartRateBpm>"))
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>255</Value></HeartRateBpm>"))  // the 300 sample
        XCTAssertFalse(xml.contains("<Value>300</Value>"))
        XCTAssertFalse(xml.contains("<Value>999</Value>"))
    }
}
