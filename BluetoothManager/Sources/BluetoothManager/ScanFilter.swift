import Foundation
import CoreBluetooth

/// 扫描过滤器协议：用于判断一个发现项是否匹配过滤条件
public protocol ScanFilter {
    /// 检查给定发现项是否匹配过滤
    /// - Parameters:
    ///   - peripheral: 发现的外围设备
    ///   - advertisementData: 广播数据
    ///   - rssi: 信号强度
    func matches(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) -> Bool
}

/// 按设备名匹配（可选大小写不敏感）
public struct NameFilter: ScanFilter {
    public let substring: String
    public let caseInsensitive: Bool

    public init(substring: String, caseInsensitive: Bool = true) {
        self.substring = substring
        self.caseInsensitive = caseInsensitive
    }

    public func matches(peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) -> Bool {
        // 首先尝试 peripheral.name，其次尝试广播数据的本地名称字段
        var name: String? = peripheral.name
        if name == nil, let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            name = advName
        }
        guard let n = name else { return false }
        if caseInsensitive {
            return n.range(of: substring, options: .caseInsensitive) != nil
        } else {
            return n.contains(substring)
        }
    }
}

/// 按广播的服务 UUID 列表匹配（如果广播中包含任意一个目标 UUID 则匹配）
public struct ServiceFilter: ScanFilter {
    public let uuids: [CBUUID]

    public init(uuids: [CBUUID]) {
        self.uuids = uuids
    }

    public func matches(peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) -> Bool {
        guard let advServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else { return false }
        for u in uuids {
            if advServices.contains(u) { return true }
        }
        return false
    }
}

/// 组合过滤器，支持 AND / OR
public struct CompositeFilter: ScanFilter {
    public enum Op {
        case all // AND
        case any // OR
    }

    public let op: Op
    public let filters: [ScanFilter]

    public init(op: Op = .all, filters: [ScanFilter]) {
        self.op = op
        self.filters = filters
    }

    public func matches(peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) -> Bool {
        switch op {
        case .all:
            for f in filters {
                if !f.matches(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi) { return false }
            }
            return true
        case .any:
            for f in filters {
                if f.matches(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi) { return true }
            }
            return false
        }
    }
}

// 便捷工厂：把任意多个过滤器合成 AND
public extension ScanFilter {
    static func all(_ filters: ScanFilter...) -> CompositeFilter {
        CompositeFilter(op: .all, filters: filters)
    }
    static func any(_ filters: ScanFilter...) -> CompositeFilter {
        CompositeFilter(op: .any, filters: filters)
    }
}
