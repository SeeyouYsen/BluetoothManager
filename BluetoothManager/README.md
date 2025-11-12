# BluetoothManager

A minimal Swift Package for basic CoreBluetooth management (scan/connect).\n
## Usage

- Add this package to your App via Xcode (File → Add Packages...) or by adding the package URL/local path.
- In your app:

```swift
import BluetoothManager

let mgr = BluetoothManager.shared
NotificationCenter.default.addObserver(forName: Notification.Name("BluetoothManagerDidDiscover"), object: nil, queue: .main) { note in
    if let peripheral = note.object as? CBPeripheral {
        print("Discovered: \(peripheral)")
    }
}
```

## Notes
- Remember to add appropriate Info.plist privacy keys in your App (e.g. `NSBluetoothAlwaysUsageDescription`).
- This package links `CoreBluetooth` via `linkerSettings` in `Package.swift`.
