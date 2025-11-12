import Foundation
import CoreBluetooth
import Combine

    /// Device-level errors used by async read/write
    public enum DeviceError: Error {
        case readTimeout
        case writeTimeout
    }

/// 表示已发现的蓝牙设备的模型。
/// 保存对底层 `CBPeripheral` 的强引用，并存储最新的广播数据、RSSI 及最后一次发现时间。
public final class BluetoothDevice: NSObject, ObservableObject, CBPeripheralDelegate {
    public let peripheral: CBPeripheral
    @Published public private(set) var advertisementData: [String: Any]
    @Published public private(set) var rssi: NSNumber
    @Published public private(set) var lastSeen: Date
    // Discovered services and characteristics (populated by BluetoothManager via CBPeripheralDelegate)
    @Published public private(set) var services: [CBService] = []
    @Published public private(set) var characteristics: [CBUUID: [CBCharacteristic]] = [:]
    /// Latest known value for characteristics
    @Published public private(set) var characteristicValues: [CBUUID: Data] = [:]

    // Publishers for characteristic updates keyed by characteristic UUID
    private var characteristicSubjects: [CBUUID: PassthroughSubject<(Data?, Error?), Never>] = [:]

    /// Return a publisher for a characteristic UUID. Emits Data when value updates and fails by throwing an Error when an error occurs.
    public func publisher(for uuid: CBUUID) -> AnyPublisher<Data, Error> {
        if characteristicSubjects[uuid] == nil {
            characteristicSubjects[uuid] = PassthroughSubject<(Data?, Error?), Never>()
        }
        return characteristicSubjects[uuid]!
            .tryCompactMap { value, error in
                if let err = error { throw err }
                return value
            }
            .eraseToAnyPublisher()
    }

    /// Enable notifications for a characteristic and return a publisher that emits incoming notification data.
    /// Caller should retain the returned AnyCancellable to keep subscription alive.
    public func subscribeToNotifications(for characteristic: CBCharacteristic) -> AnyPublisher<Data, Error> {
        // Ensure subject exists
        let uuid = characteristic.uuid
        if characteristicSubjects[uuid] == nil {
            characteristicSubjects[uuid] = PassthroughSubject<(Data?, Error?), Never>()
        }
        // Enable notifications on peripheral
        peripheral.setNotifyValue(true, for: characteristic)
        return publisher(for: uuid)
    }

    // Continuations for async read/write operations
    private var readContinuations: [CBUUID: [CheckedContinuation<Data?, Error>]] = [:]
    private var writeContinuations: [CBUUID: [CheckedContinuation<Void, Error>]] = [:]

    public var name: String? { peripheral.name }
    public var identifier: UUID { peripheral.identifier }
    /// 便捷获取 UUID 的字符串表示
    public var uuidString: String { peripheral.identifier.uuidString }

    public init(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber, lastSeen: Date = Date()) {
        self.peripheral = peripheral
        self.advertisementData = advertisementData
        self.rssi = rssi
        self.lastSeen = lastSeen
        super.init()
    }

    /// 更新存储的广播数据、RSSI 和最后发现时间
    public func update(advertisementData: [String: Any], rssi: NSNumber, lastSeen: Date = Date()) {
        self.advertisementData = advertisementData
        self.rssi = rssi
        self.lastSeen = lastSeen
    }

    /// Update discovered services
    public func updateServices(_ services: [CBService]) {
        self.services = services
    }

    /// Update characteristics for a given service
    public func updateCharacteristics(for service: CBService, characteristics: [CBCharacteristic]?) {
        self.characteristics[service.uuid] = characteristics ?? []
    }

    // MARK: - Peripheral operations

    /// Discover services for this peripheral
    public func discoverServices(_ uuids: [CBUUID]? = nil) {
        peripheral.discoverServices(uuids)
    }

    /// Discover characteristics for a given service
    public func discoverCharacteristics(for service: CBService, uuids: [CBUUID]? = nil) {
        peripheral.discoverCharacteristics(uuids, for: service)
    }

    /// Read characteristic value
    public func readCharacteristic(_ characteristic: CBCharacteristic) {
        peripheral.readValue(for: characteristic)
    }

    /// Async read: waits for didUpdateValueFor to be called or times out
    public func readCharacteristic(_ characteristic: CBCharacteristic, timeout: TimeInterval = 5) async throws -> Data? {
        let uuid = characteristic.uuid
        // Trigger read
        peripheral.readValue(for: characteristic)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            var list = readContinuations[uuid] ?? []
            list.append(continuation)
            readContinuations[uuid] = list

            // schedule timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self else { return }
                if let conts = self.readContinuations.removeValue(forKey: uuid) {
                    for c in conts {
                        c.resume(throwing: DeviceError.readTimeout)
                    }
                }
            }
        }
    }

    /// Write characteristic value
    public func writeCharacteristic(_ characteristic: CBCharacteristic, data: Data, type: CBCharacteristicWriteType = .withResponse) {
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    /// Async write: waits for didWriteValueFor to confirm or times out
    public func writeCharacteristic(_ characteristic: CBCharacteristic, data: Data, type: CBCharacteristicWriteType = .withResponse, timeout: TimeInterval = 5) async throws {
        let uuid = characteristic.uuid
        peripheral.writeValue(data, for: characteristic, type: type)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var list = writeContinuations[uuid] ?? []
            list.append(continuation)
            writeContinuations[uuid] = list

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self else { return }
                if let conts = self.writeContinuations.removeValue(forKey: uuid) {
                    for c in conts {
                        c.resume(throwing: DeviceError.writeTimeout)
                    }
                }
            }
        }
    }

    /// Enable or disable notifications for a characteristic
    public func setNotify(_ characteristic: CBCharacteristic, enabled: Bool) {
        peripheral.setNotifyValue(enabled, for: characteristic)
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        DispatchQueue.main.async {
            let services = peripheral.services ?? []
            self.updateServices(services)
            // Auto-discover characteristics for each service to populate model
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        DispatchQueue.main.async {
            self.updateCharacteristics(for: service, characteristics: service.characteristics)
            // Publish discovered characteristic values placeholders (actual values may arrive via didUpdateValue)
            for char in service.characteristics ?? [] {
                let uuid = char.uuid
                // ensure subject exists
                if self.characteristicSubjects[uuid] == nil {
                    self.characteristicSubjects[uuid] = PassthroughSubject<(Data?, Error?), Never>()
                }
                // set empty value if none
                if self.characteristicValues[uuid] == nil {
                    self.characteristicValues[uuid] = Data()
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Value updated — higher level can observe characteristic values by reading peripheral directly or extending model
        DispatchQueue.main.async {
            let uuid = characteristic.uuid
            if let err = error {
                // notify subject
                self.characteristicSubjects[uuid]?.send((nil, err))
                // resume read continuations with error
                if let conts = self.readContinuations.removeValue(forKey: uuid) {
                    for c in conts { c.resume(throwing: err) }
                }
            } else {
                let value = characteristic.value
                if let v = value { self.characteristicValues[uuid] = v }
                self.characteristicSubjects[uuid]?.send((characteristic.value, nil))
                // resume read continuations
                if let conts = self.readContinuations.removeValue(forKey: uuid) {
                    for c in conts { c.resume(returning: characteristic.value) }
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // Write completed — can be surfaced to UI via notifications or Combine subjects if needed
        DispatchQueue.main.async {
            let uuid = characteristic.uuid
            if let err = error {
                if let conts = self.writeContinuations.removeValue(forKey: uuid) {
                    for c in conts { c.resume(throwing: err) }
                }
                self.characteristicSubjects[uuid]?.send((nil, err))
            } else {
                if let conts = self.writeContinuations.removeValue(forKey: uuid) {
                    for c in conts { c.resume(returning: ()) }
                }
                self.characteristicSubjects[uuid]?.send((characteristic.value, nil))
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        DispatchQueue.main.async {
            // no-op for now; characteristic.notificationState changed
        }
    }
}
