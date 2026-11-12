import IOBluetooth
import XCTest
@testable import NotchIsland

final class BluetoothTests: XCTestCase {
    private let phone = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone)
    private let computer = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorComputer)
    private let audio = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
    private let peripheral = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral)

    func testAccessoriesAreAnnounced() {
        XCTAssertTrue(BluetoothService.isAccessory(majorClass: audio, name: "Aatman's AirPods Pro"))
        XCTAssertTrue(BluetoothService.isAccessory(majorClass: peripheral, name: "Magic Keyboard"))
    }

    func testPhonesAndComputersAreSkipped() {
        XCTAssertFalse(BluetoothService.isAccessory(majorClass: phone, name: "iPhone"))
        XCTAssertFalse(BluetoothService.isAccessory(majorClass: computer, name: "Studio"))
    }

    func testAppleDevicesAreSkippedByNameWhateverTheirClass() {
        XCTAssertFalse(BluetoothService.isAccessory(majorClass: 0, name: "Aatman's iPhone"))
        XCTAssertFalse(BluetoothService.isAccessory(majorClass: 0, name: "iPad Air"))
        XCTAssertFalse(BluetoothService.isAccessory(majorClass: 0, name: "Work MacBook Pro"))
    }

    func testReconnectingSoonAfterIsNotNews() {
        let now = Date()
        XCTAssertTrue(BluetoothService.isNews(lastAnnounced: nil, now: now))
        XCTAssertFalse(BluetoothService.isNews(lastAnnounced: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(BluetoothService.isNews(lastAnnounced: now.addingTimeInterval(-BluetoothService.repeatWindow - 1), now: now))
    }
}
