// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "BluetoothManager",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "BluetoothManager", targets: ["BluetoothManager"]),
    ],
    targets: [
        .target(
            name: "BluetoothManager",
            path: "Sources/BluetoothManager",
            linkerSettings: [
                .linkedFramework("CoreBluetooth")
            ]
        ),
        .testTarget(
            name: "BluetoothManagerTests",
            dependencies: ["BluetoothManager"],
            path: "Tests/BluetoothManagerTests"
        )
    ]
)
