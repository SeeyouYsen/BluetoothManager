//
//  ContentView.swift
//  BleExample
//
//  Created by I4Season on 2025/11/11.
//

import SwiftUI
import BluetoothManager

struct ContentView: View {
    // Observe the shared manager to get updates
    @ObservedObject private var manager = BluetoothManager.shared
    @State private var showErrorAlert = false
    @State private var errorMessage: String = ""
    var body: some View {
        NavigationView {
            TabView {
                // Discovered Tab
                List {
                    ForEach(manager.discoveredDevices, id: \.uuidString) { device in
                        NavigationLink(destination: DeviceDetailView(device: device)) {
                            DeviceRow(device: device)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .tabItem {
                    Label("Discovered", systemImage: "magnifyingglass")
                }

                // Connecting Tab
                List {
                    ForEach(manager.connectingDevices, id: \.uuidString) { device in
                        HStack {
                            Text(device.name ?? "Unknown")
                            Spacer()
                            Text("Connecting...")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .tabItem {
                    Label("Connecting", systemImage: "bolt.horizontal")
                }

                // Connected Tab
                List {
                    ForEach(manager.connectedDevices, id: \.uuidString) { device in
                        HStack {
                            Text(device.name ?? "Unknown")
                            Spacer()
                            Text("Connected")
                                .foregroundColor(.green)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .tabItem {
                    Label("Connected", systemImage: "link")
                }
            }
            .navigationTitle("BLE Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading) {
                        Text(manager.isPoweredOn ? "Bluetooth: On" : "Bluetooth: Off")
                            .font(.headline)
                        Text(manager.isScanning ? "Scanning…" : "Idle")
                            .font(.caption)
                            .foregroundColor(manager.isScanning ? .green : .secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if manager.isScanning {
                            manager.stopScan()
                        } else if manager.isPoweredOn {
                            manager.startScan()
                        }
                    }) {
                        Text(manager.isScanning ? "Stop Scan" : "Start Scan")
                    }
                }
            }
        }
        .onAppear {
            // Do not call startScan immediately — wait until central reports poweredOn so scan isn't dropped.
            // If central is already poweredOn, start now.
            if manager.isPoweredOn {
                manager.startScan()
            }
        }
        .onReceive(manager.$isPoweredOn) { powered in
            if powered {
                manager.startScan()
            }
        }
        .onDisappear {
            manager.stopScan()
        }
        .onReceive(manager.$lastError) { newErr in
            if let e = newErr {
                errorMessage = String(describing: e)
                showErrorAlert = true
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

struct DeviceRow: View {
    let device: BluetoothDevice
    @ObservedObject private var manager = BluetoothManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.name ?? "Unknown")
                    .font(.body)
                Text(device.uuidString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("RSSI: \(device.rssi)")
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: connect) {
                Text(buttonTitle)
            }
            .buttonStyle(.bordered)
            .padding(.leading, 8)
        }
        .padding(.vertical, 6)
    }

    private var buttonTitle: String {
        if manager.connectedDevices.contains(where: { $0.uuidString == device.uuidString }) {
            return "Disconnect"
        }
        if manager.connectingDevices.contains(where: { $0.uuidString == device.uuidString }) {
            return "Connecting"
        }
        return "Connect"
    }

    private func connect() {
        if manager.connectedDevices.contains(where: { $0.uuidString == device.uuidString }) {
            manager.disconnect(peripheral: device.peripheral)
            return
        }

        Task {
            do {
                _ = try await manager.connect(device: device)
                // connected — UI will update via published properties
            } catch {
                print("Connect failed: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}
