import Foundation
import WhoopProtocol
import WhoopStore

/// Serializes ONE cached workout row + its raw HR window into a Garmin Training Center (TCX v2)
/// document — the per-workout interchange file Strava / intervals.icu accept. The write-side dual of
/// TcxParser, pinned by TcxExporterTests, which re-parse this output with the REAL parser and assert
/// field-level equality — so any structural drift fails a test rather than silently producing an
/// un-importable file.
///
/// The Activity's Sport attribute is a RESTRICTED schema enum (Running | Biking | Other), so the
/// free-text sport is mapped down and the REAL label rides in <Notes> — nothing is lost, and every
/// consumer still gets a schema-valid value. Trackpoints are HR-only: the stored route polyline
/// carries no per-point timestamps, so an honest GPS track can't be reconstructed — distance and
/// calories ride in the Lap summary instead. An HR-empty window still emits a valid document (Lap
/// summary with the Track element omitted, since an empty Track is schema-invalid), which Strava accepts.
public enum TcxExporter {

    // MARK: - Primitives

    /// Fixed UTC ISO-8601 formatter (trailing Z) — one instance, en_US_POSIX so the format is stable
    /// across locales. The only <Time> encoding every TCX consumer parses.
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    static func iso(_ ts: Int) -> String {
        isoFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Minimal XML text/attribute escaping. `&` FIRST, or the other escapes get re-escaped.
    static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Locale-proof numbers, mirroring WhoopCsvExporter.num: integral Doubles print without a
    /// trailing ".0", and String(Double) always uses '.' as the separator.
    static func num(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e12 ? String(Int64(v)) : String(v)
    }

    /// Clamp a heart rate to the schema's `HeartRateInBeatsPerMinute_t/Value` domain: `positiveByte`,
    /// i.e. 1–255. Importer-sourced avgHr/maxHr are unbounded Ints, and a stray 0 / >255 makes the
    /// document fail XSD validation on strict consumers.
    static func hrValue(_ bpm: Int) -> Int { min(max(bpm, 1), 255) }

    /// Map the free-text sport onto the schema's restricted Sport enum. Everything unrecognized is
    /// honestly "Other" — the real label rides in <Notes>, never fabricated into a claimed sport.
    static func schemaSport(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("run") { return "Running" }
        if lower.contains("bik") || lower.contains("cycl") || lower.contains("ride") { return "Biking" }
        return "Other"
    }

    /// The free text the restricted Sport attribute can't carry: the real sport label, the row's own
    /// notes when present, and provenance. Escaped at the embed site.
    static func notesText(_ row: WorkoutRow) -> String {
        var parts = [row.sport]
        if let n = row.notes, !n.isEmpty { parts.append(n) }
        parts.append("exported by NOOP")
        return parts.joined(separator: " · ")
    }

    // MARK: - Document

    /// One workout row + its raw HR window as a complete TCX v2 document. Pure — the caller supplies
    /// the HR samples (already ascending from the store read) and presents the string however it likes.
    public static func tcx(_ row: WorkoutRow, hr: [HRSample]) -> String {
        let start = iso(row.startTs)
        let totalS = row.durationS ?? Double(max(0, row.endTs - row.startTs))

        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">"#,
            "  <Activities>",
            "    <Activity Sport=\"\(schemaSport(row.sport))\">",
            "      <Id>\(start)</Id>",
            "      <Lap StartTime=\"\(start)\">",
            "        <TotalTimeSeconds>\(num(totalS))</TotalTimeSeconds>",
        ]
        // DistanceMeters and Calories are REQUIRED in ActivityLap_t (no minOccurs), so emit them
        // unconditionally in schema order — 0 when the row carried nothing, never omitted. A missing
        // element makes the whole document fail strict XSD validation on some consumers.
        let dist = (row.distanceM.map { $0.isFinite && $0 > 0 ? $0 : 0 }) ?? 0
        lines.append("        <DistanceMeters>\(num(dist))</DistanceMeters>")
        // Calories is xsd:unsignedShort — clamp so a corrupt row can't emit an invalid value.
        let kcal = (row.energyKcal.map { $0.isFinite && $0 > 0 ? $0 : 0 }) ?? 0
        lines.append("        <Calories>\(Int(min(kcal.rounded(), 65_535)))</Calories>")
        if let avg = row.avgHr, avg > 0 {
            lines.append("        <AverageHeartRateBpm><Value>\(hrValue(avg))</Value></AverageHeartRateBpm>")
        }
        if let mx = row.maxHr, mx > 0 {
            lines.append("        <MaximumHeartRateBpm><Value>\(hrValue(mx))</Value></MaximumHeartRateBpm>")
        }
        lines.append("        <Intensity>Active</Intensity>")
        lines.append("        <TriggerMethod>Manual</TriggerMethod>")
        // Track_t requires Trackpoint minOccurs=1, and Lap's Track is itself optional (minOccurs=0),
        // so the honest encoding of an HR-empty window is to OMIT <Track> entirely rather than emit an
        // empty one (which is schema-invalid). Consumers read the Lap summary instead.
        let points = hr.filter { $0.bpm > 0 }
        if !points.isEmpty {
            lines.append("        <Track>")
            for s in points {
                lines.append("          <Trackpoint>")
                lines.append("            <Time>\(iso(s.ts))</Time>")
                lines.append("            <HeartRateBpm><Value>\(hrValue(s.bpm))</Value></HeartRateBpm>")
                lines.append("          </Trackpoint>")
            }
            lines.append("        </Track>")
        }
        lines.append("      </Lap>")
        lines.append("      <Notes>\(escape(notesText(row)))</Notes>")
        lines.append("    </Activity>")
        lines.append("  </Activities>")
        lines.append("</TrainingCenterDatabase>")
        return lines.joined(separator: "\n") + "\n"
    }
}
