import Testing
@testable import DiscScannerCore

@Test func packageVersionIsSet() {
    #expect(DiscScannerCore.version == "0.1.0")
}
