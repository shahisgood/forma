import Foundation

/// A body-mass sample read from Apple Health, reduced to the fields needed for import decisions.
public struct IncomingWeightSample: Hashable, Sendable {
    public var uuid: String
    public var date: Date
    public var kilograms: Double
    public var sourceBundleID: String
    public var sourceName: String
    /// `HKMetadataKeyExternalUUID`, set by Forma when it writes a sample.
    public var externalID: String?

    public init(uuid: String, date: Date, kilograms: Double, sourceBundleID: String, sourceName: String, externalID: String?) {
        self.uuid = uuid
        self.date = date
        self.kilograms = kilograms
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.externalID = externalID
    }
}

public struct WeightImportPlan: Equatable, Sendable {
    public var toInsert: [IncomingWeightSample]
    /// Samples Forma wrote itself (already present locally as the original entry).
    public var skippedOwn: Int
    /// Samples already imported earlier.
    public var skippedExisting: Int
    /// Samples with implausible values.
    public var skippedInvalid: Int
}

/// Decides which Health samples become local entries, so repeated imports and
/// Forma's own writes never create duplicates.
public enum HealthImportDeduplicator {
    /// Plausible body-mass range in kilograms.
    public static let plausibleRange = 20.0...400.0

    public static func plan(
        incoming: [IncomingWeightSample],
        appBundleID: String,
        importedSampleUUIDs: Set<String>,
        localEntryIDs: Set<String>,
        writtenSampleUUIDs: Set<String>
    ) -> WeightImportPlan {
        var seen = Set<String>()
        var insert: [IncomingWeightSample] = []
        var own = 0
        var existing = 0
        var invalid = 0

        for sample in incoming {
            let isOwnSource = !appBundleID.isEmpty
                && (sample.sourceBundleID == appBundleID || sample.sourceBundleID.hasPrefix(appBundleID + "."))
            if isOwnSource
                || writtenSampleUUIDs.contains(sample.uuid)
                || (sample.externalID.map(localEntryIDs.contains) ?? false) {
                own += 1
                continue
            }
            if importedSampleUUIDs.contains(sample.uuid) || seen.contains(sample.uuid) {
                existing += 1
                continue
            }
            guard sample.kilograms.isFinite, plausibleRange.contains(sample.kilograms) else {
                invalid += 1
                continue
            }
            seen.insert(sample.uuid)
            insert.append(sample)
        }
        return WeightImportPlan(toInsert: insert, skippedOwn: own, skippedExisting: existing, skippedInvalid: invalid)
    }
}

/// A tiny CSV writer (RFC 4180 quoting).
public struct CSVTable: Sendable {
    public var header: [String]
    public var rows: [[String]]

    public init(header: [String], rows: [[String]] = []) {
        self.header = header
        self.rows = rows
    }

    public static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    public func render() -> String {
        ([header] + rows)
            .map { $0.map(Self.escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    public static func number(_ value: Double?, fractionDigits: Int = 2) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(fractionDigits)f", value)
    }

    public static func timestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
