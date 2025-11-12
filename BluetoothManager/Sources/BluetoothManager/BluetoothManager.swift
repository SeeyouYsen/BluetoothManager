import Foundation
import CoreBluetooth
import Combine

// 文件级 helper：安排连接超时处理，不捕获 `self`（只捕获 uuid）以避免在 @Sendable 闭包中捕获非 Sendable 的类型
fileprivate func scheduleConnectionTimeout(for uuid: String, after seconds: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        Task {
            await MainActor.run {
                if let continuations = BluetoothManager.shared.connectionContinuations.removeValue(forKey: uuid) {
                    // surface timeout to UI
                    BluetoothManager.shared.lastError = BluetoothManager.BluetoothConnectionError.timeout
                    for cont in continuations {
                        cont.resume(throwing: BluetoothManager.BluetoothConnectionError.timeout)
                    }
                }
            }
        }
    }
}

public final class BluetoothManager: NSObject, ObservableObject {
    public static let shared = BluetoothManager()

    private var central: CBCentralManager!
    @Published public private(set) var isPoweredOn: Bool = false

    // 保持已发现设备的强引用（包装为 BluetoothDevice）以便可以连接
    // 使用 uuid 字符串作为字典 key，便于序列化/跨进程打印
    private var discoveredPeripherals: [String: BluetoothDevice] = [:]
    // 正在连接的设备（已发起 connect，但尚未建立连接）
    private var connectingPeripherals: [String: BluetoothDevice] = [:]
    // 已连接的设备
    private var connectedPeripherals: [String: BluetoothDevice] = [:]

    /// 使用 Combine 的发布属性，外部可以订阅这些属性以获取实时更新
    @Published public private(set) var discoveredDevices: [BluetoothDevice] = []
    @Published public private(set) var connectingDevices: [BluetoothDevice] = []
    @Published public private(set) var connectedDevices: [BluetoothDevice] = []
    // Expose last error for UI (connection/read/write) to observe
    @Published public var lastError: Error?
    // Expose scanning state
    @Published public private(set) var isScanning: Bool = false

    // 当前扫描使用的过滤器（若非 nil，则在 didDiscover 中以该过滤器筛选）
    private var scanFilter: ScanFilter?
    // 连接异步等待者：允许多个并发等待同一个设备的连接结果
    fileprivate var connectionContinuations: [String: [CheckedContinuation<Bool, Error>]] = [:]
    // 每个设备的 Combine 订阅，用于监听设备自身属性变化并转发为 manager 的 published 更新
    private var deviceSubscriptions: [String: AnyCancellable] = [:]

    public enum BluetoothConnectionError: Error {
        case timeout
        case failed(Error?)
    }

    public override init() {
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil)
    }

    /// 开始扫描，可按服务 UUID（由系统过滤）和/或自定义的 `ScanFilter` 进行过滤。
    /// - Parameters:
    ///   - serviceUUIDs: 要扫描的服务 UUID 列表（传 nil 表示不过滤服务）
    ///   - filter: 自定义筛选器，在 `didDiscover` 时使用（传 nil 表示不过滤）
    public func startScan(serviceUUIDs: [CBUUID]? = nil, filter: ScanFilter? = nil) {
        guard isPoweredOn else { return }
        // 保存过滤器以便在 didDiscover 中使用
        scanFilter = filter
        central.scanForPeripherals(withServices: serviceUUIDs, options: nil)
        isScanning = true
    }

    public func stopScan() {
        central.stopScan()
        // 清除扫描时的临时过滤器
        scanFilter = nil
        isScanning = false
    }

    // 连接指定的外设，确保保存强引用并将其标记为“正在连接”
    public func connect(peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        let device: BluetoothDevice
        if let existing = discoveredPeripherals[uuid] {
            device = existing
        } else {
            device = BluetoothDevice(peripheral: peripheral, advertisementData: [:], rssi: NSNumber(value: 0))
            discoveredPeripherals[uuid] = device
            subscribeToDeviceChanges(device)
        }
        connectingPeripherals[uuid] = device
        // 刷新 published 列表，外部订阅者会收到更新
        connectingDevices = Array(connectingPeripherals.values)
        discoveredDevices = Array(discoveredPeripherals.values)
        notifyStartConnectingIfNeeded(device)
        central.connect(peripheral, options: nil)
    }

    /// 异步连接到指定的 BluetoothDevice，返回 true 表示连接成功，抛出错误表示失败或超时
    /// - Parameters:
    ///   - device: 要连接的设备模型
    ///   - timeout: 超时时间（秒），默认为 10 秒
    public func connect(device: BluetoothDevice, timeout: TimeInterval = 10) async throws -> Bool {
        let uuid = device.uuidString

        // 如果已连接，直接返回
        if connectedPeripherals[uuid] != nil {
            return true
        }

        // 发起连接（如果尚未发起，这个方法也会把 device 加入 connectingPeripherals）
        if connectingPeripherals[uuid] == nil {
            connect(peripheral: device.peripheral)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            // 将 continuation 存储以便在 delegate 回调时恢复
            var list = connectionContinuations[uuid] ?? []
            list.append(continuation)
            connectionContinuations[uuid] = list

            // 设置超时处理：到时如果还没恢复就当作超时错误
            scheduleConnectionTimeout(for: uuid, after: timeout)
        }
    }

    // 取消连接
    public func disconnect(peripheral: CBPeripheral) {
        central.cancelPeripheralConnection(peripheral)
    }

    // 内部：在开始连接时，触发任何需要的逻辑（目前保留为扩展点）
    private func notifyStartConnectingIfNeeded(_ device: BluetoothDevice) {
        // 占位：目前通过 published 属性实现更新，保留此方法便于未来扩展
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Update power state
        switch central.state {
        case .poweredOn:
            isPoweredOn = true
        default:
            isPoweredOn = false
        }

        // On iOS 13+ we can inspect authorization. If denied/restricted, surface to UI so app can guide user to Settings.
        if #available(iOS 13.1, *) {
            switch CBManager.authorization {
            case .allowedAlways:
                break
            case .notDetermined:
                // not determined; the system will prompt when we scan/connect
                break
            case .denied, .restricted:
                // surface a user-friendly error for UI
                DispatchQueue.main.async {
                    self.lastError = NSError(domain: "Bluetooth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bluetooth permission denied or restricted. Please enable Bluetooth permission in Settings."])
                }
            @unknown default:
                break
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    // 保持强引用，防止 peripheral 被释放
    // 先进行过滤（若有配置的 filter）
    if let f = scanFilter, !f.matches(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI) {
        return
    }
    let uuid = peripheral.identifier.uuidString
    let device = discoveredPeripherals[uuid] ?? BluetoothDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
    device.update(advertisementData: advertisementData, rssi: RSSI, lastSeen: Date())
    if discoveredPeripherals[uuid] == nil {
        discoveredPeripherals[uuid] = device
        subscribeToDeviceChanges(device)
    } else {
        // 已存在则更新引用（设备对象已更新）
        discoveredPeripherals[uuid] = device
    }
        // 更新发布列表，通知订阅者
        discoveredDevices = Array(discoveredPeripherals.values)
        // 如果该设备已在正在连接集合中，发出更新（通过 published connectingDevices）
        if connectingPeripherals[uuid] != nil {
                // no-op for now: connectingDevices already contains reference; refresh published value
                connectingDevices = Array(connectingPeripherals.values)
            }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Move from connecting -> connected if present
        let uuid = peripheral.identifier.uuidString
        if let device = discoveredPeripherals[uuid] {
            connectingPeripherals.removeValue(forKey: uuid)
            connectedPeripherals[uuid] = device
            // Assign peripheral delegate to device for per-device management
            peripheral.delegate = device
            // Trigger service discovery at device level
            device.discoverServices(nil)
            // 刷新 published 列表，通知订阅者
            connectingDevices = Array(connectingPeripherals.values)
            connectedDevices = Array(connectedPeripherals.values)
            // 恢复所有等待该 uuid 的 continuation（成功）
            if let continuations = connectionContinuations.removeValue(forKey: uuid) {
                for cont in continuations {
                    cont.resume(returning: true)
                }
            }
        }
    }

    // 取消对设备属性变化的订阅并移除订阅记录
    private func unsubscribeFromDeviceChanges(uuid: String) {
        if let sub = deviceSubscriptions.removeValue(forKey: uuid) {
            sub.cancel()
        }
    }

    // 订阅单个设备的属性变化，并在变化时刷新 manager 的 published 列表
    private func subscribeToDeviceChanges(_ device: BluetoothDevice) {
        let uuid = device.uuidString
        // 先取消已有的订阅（如果有）
        deviceSubscriptions[uuid]?.cancel()
        let cancellable = device.objectWillChange.sink { [weak self] _ in
            guard let self = self else { return }
            // 当设备内部属性变化时，刷新 published 列表以广播变化
            self.discoveredDevices = Array(self.discoveredPeripherals.values)
            self.connectingDevices = Array(self.connectingPeripherals.values)
            self.connectedDevices = Array(self.connectedPeripherals.values)
        }
        deviceSubscriptions[uuid] = cancellable
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // remove from connecting if present
        let uuid = peripheral.identifier.uuidString
        if let device = connectingPeripherals.removeValue(forKey: uuid) {
            // 刷新 published 列表并通知失败（通过 published 更新）
            connectingDevices = Array(connectingPeripherals.values)
            // 恢复所有等待该 uuid 的 continuation（失败）
            if let continuations = connectionContinuations.removeValue(forKey: uuid) {
                // surface error to UI
                BluetoothManager.shared.lastError = BluetoothConnectionError.failed(error)
                for cont in continuations {
                    cont.resume(throwing: BluetoothConnectionError.failed(error))
                }
            }
            _ = device
            // 如果我们因为连接失败要移除设备，可以取消订阅（保持与 discoveredPeripherals 的一致性）
            // 这里我们不自动移除 discoveredPeripherals，但如果移除时应清理订阅，请调用 unsubscribeFromDeviceChanges(uuid:)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // remove from connected list
        let uuid = peripheral.identifier.uuidString
        if let device = connectedPeripherals.removeValue(forKey: uuid) {
            // 刷新 published 列表
            connectedDevices = Array(connectedPeripherals.values)
            // Optionally移除强引用（与先前保持一致）
            discoveredPeripherals.removeValue(forKey: uuid)
            discoveredDevices = Array(discoveredPeripherals.values)
            // 取消对该设备的属性订阅
            unsubscribeFromDeviceChanges(uuid: uuid)
            _ = device
        }
    }
}
