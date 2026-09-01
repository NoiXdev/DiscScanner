import Foundation

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func count(_ value: Int) -> String {
        value.formatted()
    }

    /// Signed byte count for comparison tables: the sign is the point.
    static func signedBytes(_ value: Int64) -> String {
        let formatted = bytes(abs(value))
        if value > 0 { return "+" + formatted }
        if value < 0 { return "-" + formatted }
        return formatted
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(1)))
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
