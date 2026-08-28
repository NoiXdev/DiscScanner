public struct ScanProgress: Sendable, Equatable {
    public var filesScanned = 0
    public var directoriesScanned = 0
    public var totalBytes: Int64 = 0
    public var accessDeniedCount = 0
    public var currentPath = ""

    public init() {}
}
