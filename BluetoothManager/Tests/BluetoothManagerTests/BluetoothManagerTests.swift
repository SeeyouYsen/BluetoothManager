import XCTest
@testable import BluetoothManager

final class BluetoothManagerTests: XCTestCase {
    func testSharedInstanceNonNil() {
        XCTAssertNotNil(BluetoothManager.shared)
    }
}
