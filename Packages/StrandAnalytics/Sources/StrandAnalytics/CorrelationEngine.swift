import Foundation

// CorrelationEngine.swift — relationships between two daily series.
//
// Pure, deterministic, DB-free. Computes the Pearson product-moment correlation r,
// a simple ordinary-least-squares regression line (slope/intercept of y on x), and
// a two-sided Student-t p-value for r.
//
//   r = Σ(x−x̄)(y−ȳ) / sqrt( Σ(x−x̄)² · Σ(y−ȳ)² )         (Pearson)
//   slope     = Σ(x−x̄)(y−ȳ) / Σ(x−x̄)²                     (OLS, y on x)
//   intercept = ȳ − slope·x̄
//
// The p-value uses the standard t-statistic for a correlation,
//   t = r · sqrt( (n−2) / (1−r²) ),
// converted to the EXACT two-sided Student-t tail with df = n−2 via the regularized
// incomplete beta function,
//   p = I_x( df/2, 1/2 ),   x = df / (df + t²).
// I_x is evaluated from its Lentz continued fraction (betaContinuedFraction) with a
// Foundation `lgamma` prefactor, fully deterministic across arm64/x86_64 and, unlike
// the earlier normal approximation, honest about the heavier small-n tails. The
// normal CDF Φ (Abramowitz & Stegun 7.1.26 erf) is retained because BehaviorInsights'
// Welch t-test still reads it.
//
// Family-level multiple-comparison correction is exposed separately: a caller with a
// batch of raw per-pair p-values applies `benjaminiHochberg` (FDR q-values) or
// `bonferroni` (family-wise) across the family before judging significance.
//
// `alignByDay` inner-joins two "yyyy-MM-dd"-keyed series on the day key, returning
// (x, y) pairs sorted by day. `lagged` shifts y forward by `lagDays` relative to x
// (x on day D paired with y on day D+lag) and correlates the result, which lets a
// caller probe directional / delayed effects (e.g. today's strain vs tomorrow's
// recovery).

/// The result of correlating two aligned series.
public struct Correlation: Equatable, Sendable {
    /// Pearson correlation coefficient in [-1, 1].
    public let r: Double
    /// Number of paired observations used.
    public let n: Int
    /// Raw two-sided p-value for H0: r = 0 (exact Student-t tail, df = n−2). Named
    /// `pApprox` for source compatibility; it is the per-pair value before any
    /// family-level FDR/Bonferroni correction.
    public let pApprox: Double
    /// OLS slope of y on x.
    public let slope: Double
    /// OLS intercept of y on x.
    public let intercept: Double

    public init(r: Double, n: Int, pApprox: Double, slope: Double, intercept: Double) {
        self.r = r
        self.n = n
        self.pApprox = pApprox
        self.slope = slope
        self.intercept = intercept
    }
}

public enum CorrelationEngine {

    // MARK: - Pearson + regression

    /// Pearson r plus an OLS regression line and approximate p-value for the pairs.
    /// Returns nil when fewer than 3 pairs, or when either variable has zero
    /// variance (r undefined).
    public static func pearson(_ xy: [(Double, Double)]) -> Correlation? {
        let n = xy.count
        guard n >= 3 else { return nil }
        let nD = Double(n)

        var sumX = 0.0, sumY = 0.0
        for p in xy { sumX += p.0; sumY += p.1 }
        let meanX = sumX / nD
        let meanY = sumY / nD

        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in xy {
            let dx = p.0 - meanX
            let dy = p.1 - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }

        // Zero variance in either variable → correlation undefined.
        guard sxx > 0 && syy > 0 else { return nil }

        var r = sxy / (sxx.squareRoot() * syy.squareRoot())
        // Clamp tiny floating-point overshoot so |r| ≤ 1 exactly.
        if r > 1.0 { r = 1.0 }
        if r < -1.0 { r = -1.0 }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let p = pValue(r: r, n: n)

        return Correlation(r: r, n: n, pApprox: p, slope: slope, intercept: intercept)
    }

    // MARK: - Day alignment

    /// Inner-join two "yyyy-MM-dd"-keyed series on the day key, returning the (x, y)
    /// value pairs for days present in BOTH, sorted ascending by day. Later entries
    /// for a duplicated day in either series win (last-write).
    public static func alignByDay(_ a: [(day: String, value: Double)],
                                  _ b: [(day: String, value: Double)]) -> [(Double, Double)] {
        var mapA: [String: Double] = [:]
        for row in a { mapA[row.day] = row.value }
        var mapB: [String: Double] = [:]
        for row in b { mapB[row.day] = row.value }

        let commonDays = mapA.keys.filter { mapB[$0] != nil }.sorted()
        return commonDays.map { (mapA[$0]!, mapB[$0]!) }
    }

    // MARK: - Lagged correlation

    /// Correlate x[day] against y[day + lagDays]. A positive lag asks "does x today
    /// predict y `lagDays` later?"; a negative lag looks backward. Days are matched
    /// on the calendar by offsetting x's day key by `lagDays` and joining to y.
    ///
    /// Returns nil when fewer than 3 lag-matched pairs survive or when `pearson`
    /// rejects them (zero variance).
    public static func lagged(x: [(day: String, value: Double)],
                              y: [(day: String, value: Double)],
                              lagDays: Int) -> Correlation? {
        var mapY: [String: Double] = [:]
        for row in y { mapY[row.day] = row.value }

        var pairs: [(Double, Double)] = []
        // Sort x by day for deterministic ordering of the pair list.
        let sortedX = x.sorted { $0.day < $1.day }
        for row in sortedX {
            guard let shifted = shiftDay(row.day, by: lagDays) else { continue }
            if let yv = mapY[shifted] {
                pairs.append((row.value, yv))
            }
        }
        return pearson(pairs)
    }

    // MARK: - p-value

    /// Two-sided p-value for H0: r = 0 via t = r·sqrt((n−2)/(1−r²)) and the EXACT
    /// Student-t tail with df = n−2: p = I_x(df/2, 1/2), x = df/(df + t²). n ≤ 2 → 1.0
    /// (no evidence); |r| = 1 → 0.0 (t → ∞, x → 0 → I_0 = 0).
    static func pValue(r: Double, n: Int) -> Double {
        guard n > 2 else { return 1.0 }
        let oneMinusR2 = 1.0 - r * r
        if oneMinusR2 <= 0 { return 0.0 }  // |r| == 1
        let df = Double(n - 2)
        let t = r * (df / oneMinusR2).squareRoot()
        let x = df / (df + t * t)
        return regularizedIncompleteBeta(x, df / 2.0, 0.5)
    }

    /// Standard-normal CDF Φ(z) using the A&S 7.1.26 erf approximation.
    static func normalCDF(_ z: Double) -> Double {
        0.5 * (1.0 + erfApprox(z / 2.0.squareRoot()))
    }

    /// erf(x) — Abramowitz & Stegun 7.1.26, |error| ≤ 1.5e-7.
    static func erfApprox(_ x: Double) -> Double {
        let sign = x < 0 ? -1.0 : 1.0
        let ax = abs(x)
        let t = 1.0 / (1.0 + 0.3275911 * ax)
        let y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t
                        - 0.284496736) * t + 0.254829592) * t * exp(-ax * ax)
        return sign * y
    }

    // MARK: - Regularized incomplete beta

    /// Regularized incomplete beta I_x(a, b), the CDF machinery behind the Student-t
    /// tail in `pValue`. Guards x ≤ 0 → 0 and x ≥ 1 → 1. The prefactor
    /// x^a·(1−x)^b / (a·B(a,b)) is formed in log space via Foundation `lgamma`, and the
    /// series is summed by its continued fraction, using the standard symmetry
    /// I_x(a,b) = 1 − I_{1−x}(b,a) on the slow-converging side so the CF is always
    /// evaluated where it converges fastest. Deterministic across arm64/x86_64.
    static func regularizedIncompleteBeta(_ x: Double, _ a: Double, _ b: Double) -> Double {
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        let logBeta = lgamma(a + b) - lgamma(a) - lgamma(b)
        let front = exp(logBeta + a * log(x) + b * log(1.0 - x))
        if x < (a + 1.0) / (a + b + 2.0) {
            return front * betaContinuedFraction(x, a, b) / a
        } else {
            return 1.0 - front * betaContinuedFraction(1.0 - x, b, a) / b
        }
    }

    /// Lentz continued-fraction evaluation of the incomplete-beta CF used by
    /// `regularizedIncompleteBeta`. Fixed 200-iteration cap with a 1e-12 relative
    /// tolerance and the usual 1e-30 zero-guard; touches only libm, so it is
    /// deterministic across architectures.
    private static func betaContinuedFraction(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let tiny = 1e-30
        let qab = a + b
        let qap = a + 1.0
        let qam = a - 1.0
        var c = 1.0
        var d = 1.0 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1.0 / d
        var h = d
        for m in 1...200 {
            let mD = Double(m)
            let m2 = 2.0 * mD
            // Even step: d_{2m}.
            var aa = mD * (b - mD) * x / ((qam + m2) * (a + m2))
            d = 1.0 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1.0 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1.0 / d
            h *= d * c
            // Odd step: d_{2m+1}.
            aa = -(a + mD) * (qab + mD) * x / ((a + m2) * (qap + m2))
            d = 1.0 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1.0 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1.0 / d
            let del = d * c
            h *= del
            if abs(del - 1.0) < 1e-12 { break }
        }
        return h
    }

    // MARK: - Multiple-comparison correction

    /// Benjamini–Hochberg FDR adjustment. Given m raw p-values it returns their
    /// q-values in the SAME order as the input: sort ascending, scale the rank-i value
    /// by m/i, enforce monotonicity from the largest rank down (a step-up ceiling), and
    /// clamp to 1. Empty in → empty out; a single value returns itself (m/1 = 1).
    public static func benjaminiHochberg(_ pValues: [Double]) -> [Double] {
        let m = pValues.count
        guard m > 0 else { return [] }
        let mD = Double(m)
        // Ascending order of the raw values, carrying original positions so the result
        // can be handed back in input order.
        let order = pValues.indices.sorted { pValues[$0] < pValues[$1] }
        var adjusted = [Double](repeating: 0.0, count: m)
        var ceiling = 1.0  // monotone step-up ceiling, walked from the largest rank down.
        for rank in stride(from: m, through: 1, by: -1) {
            let idx = order[rank - 1]
            let q = pValues[idx] * mD / Double(rank)
            ceiling = min(ceiling, q)
            adjusted[idx] = min(1.0, ceiling)
        }
        return adjusted
    }

    /// Bonferroni family-wise correction: multiply each raw p-value by the family size
    /// m and clamp to 1. Order-preserving; empty in → empty out.
    public static func bonferroni(_ pValues: [Double]) -> [Double] {
        let m = Double(pValues.count)
        return pValues.map { min(1.0, $0 * m) }
    }

    // MARK: - Day arithmetic

    /// Shift a "yyyy-MM-dd" day string by `delta` days (can be negative), returning
    /// a normalised "yyyy-MM-dd" string. Uses a fixed UTC calendar so it is
    /// deterministic and timezone-free. Returns nil if the input can't be parsed.
    static func shiftDay(_ day: String, by delta: Int) -> String? {
        if delta == 0 { return day }
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1 else { return nil }

        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let base = cal.date(from: comps),
              let shifted = cal.date(byAdding: .day, value: delta, to: base) else { return nil }
        let out = cal.dateComponents([.year, .month, .day], from: shifted)
        guard let oy = out.year, let om = out.month, let od = out.day else { return nil }
        return String(format: "%04d-%02d-%02d", oy, om, od)
    }
}
