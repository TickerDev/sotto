import XCTest
import SottoAudio

final class HardwareCatalogTests: XCTestCase, @unchecked Sendable {
    @MainActor func testCurrentHardwareInventoryAndListenerLifecycle() throws {
        let catalog = MicrophoneCatalog()
        defer { catalog.stop() }
        guard !catalog.devices.isEmpty else { throw XCTSkip("No physical microphone in this environment") }
        XCTAssertTrue(catalog.monitoringAvailable)
        XCTAssertTrue(catalog.devices.allSatisfy { !$0.uid.isEmpty })
        XCTAssertEqual(Set(catalog.devices.map(\.uid)).count, catalog.devices.count)
        var refreshes = 0
        catalog.changed = { refreshes += 1 }
        catalog.refresh()
        XCTAssertEqual(refreshes, 1)
        if catalog.devices.contains(where: { $0.deviceID == catalog.defaultInputID }) {
            XCTAssertEqual(try catalog.selected("").deviceID, catalog.defaultInputID)
        }
        catalog.stop()
        XCTAssertFalse(catalog.monitoringAvailable)
    }
}
