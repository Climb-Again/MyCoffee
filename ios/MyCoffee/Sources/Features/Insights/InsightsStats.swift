import Foundation

/// Pure, view-free statistics helpers for the Insights page. Gates enforced
/// here are exactly PLAN.md §6.4's, so the page can't degrade into a noise
/// generator: categorical needs n ≥ 5 in-group *and* out-group with
/// |Δmean| ≥ 0.08; ordinal needs Spearman n ≥ 20 and |ρ| ≥ 0.15. Neither
/// gate ever computes or exposes a p-value.
enum InsightsStats {

    /// A gated categorical comparison — `nil` whenever the gate fails, so
    /// callers never have to re-check thresholds themselves.
    static func categoricalDelta(group: [Double], outGroup: [Double]) -> (delta: Double, groupN: Int, outN: Int)? {
        guard group.count >= 5, outGroup.count >= 5 else { return nil }
        let groupMean = group.reduce(0, +) / Double(group.count)
        let outMean = outGroup.reduce(0, +) / Double(outGroup.count)
        let delta = groupMean - outMean
        guard abs(delta) >= 0.08 else { return nil }
        return (delta, group.count, outGroup.count)
    }

    /// Gated Spearman rank correlation between two equal-length samples.
    static func spearman(_ xs: [Double], _ ys: [Double]) -> (rho: Double, n: Int)? {
        guard xs.count == ys.count, xs.count >= 20 else { return nil }
        let n = xs.count
        let xRanks = ranks(of: xs)
        let yRanks = ranks(of: ys)
        let meanX = xRanks.reduce(0, +) / Double(n)
        let meanY = yRanks.reduce(0, +) / Double(n)

        var covariance = 0.0, varX = 0.0, varY = 0.0
        for i in 0..<n {
            let dx = xRanks[i] - meanX
            let dy = yRanks[i] - meanY
            covariance += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        guard varX > 0, varY > 0 else { return nil }
        let rho = covariance / (varX * varY).squareRoot()
        guard abs(rho) >= 0.15 else { return nil }
        return (rho, n)
    }

    /// Fractional (average) ranks — tied values share the mean rank of their run.
    private static func ranks(of values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count, values[order[j + 1]] == values[order[i]] { j += 1 }
            let averageRank = Double(i + j) / 2.0 + 1.0
            for k in i...j { result[order[k]] = averageRank }
            i = j + 1
        }
        return result
    }

    /// Within-year z-scores for a set of (year, rating) points — one
    /// person's ratings drift as taste calibrates over a decade, so a raw
    /// year-over-year comparison mistakes calibration drift for signal
    /// (PLAN.md §6.4's "two additions the brief doesn't ask for"). A year
    /// with fewer than 2 rated coffees has no defined spread, so its points
    /// pass through unscored (`nil`).
    static func withinYearZScores(_ points: [(year: Int, rating: Double)]) -> [Double?] {
        var byYear: [Int: [Double]] = [:]
        for point in points { byYear[point.year, default: []].append(point.rating) }

        var meanByYear: [Int: Double] = [:]
        var stdevByYear: [Int: Double] = [:]
        for (year, ratings) in byYear {
            guard ratings.count >= 2 else { continue }
            let mean = ratings.reduce(0, +) / Double(ratings.count)
            let variance = ratings.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(ratings.count)
            meanByYear[year] = mean
            stdevByYear[year] = variance.squareRoot()
        }

        return points.map { point in
            guard let mean = meanByYear[point.year], let stdev = stdevByYear[point.year], stdev > 0 else { return nil }
            return (point.rating - mean) / stdev
        }
    }
}
