public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case snapshot(FileNode)
    case finished(FileNode)
}
