import SwiftUI
import CoreBluetooth
import BluetoothManager
import Combine

struct DeviceDetailView: View {
    @ObservedObject var device: BluetoothDevice

    @State private var subscriptions: [CBUUID: AnyCancellable] = [:]
    @State private var values: [CBUUID: String] = [:]
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section(header: Text("Info")) {
                Text(device.name ?? "Unknown")
                Text(device.uuidString).font(.caption).foregroundColor(.secondary)
            }

            Section(header: Text("Services & Characteristics")) {
                if device.services.isEmpty {
                    Text("No services discovered")
                } else {
                    ForEach(device.services, id: \.uuid) { service in
                        VStack(alignment: .leading) {
                            Text("Service: \(service.uuid.uuidString)")
                                .font(.subheadline)
                                .bold()
                            if let chars = device.characteristics[service.uuid], !chars.isEmpty {
                                ForEach(chars, id: \.uuid) { char in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Char: \(char.uuid.uuidString)")
                                                .font(.caption)
                                            Text(values[char.uuid] ?? "(no value)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("Read") {
                                            Task {
                                                do {
                                                    let data = try await device.readCharacteristic(char)
                                                    if let d = data {
                                                        values[char.uuid] = d.map { String(format: "%02x", $0) }.joined()
                                                    } else {
                                                        values[char.uuid] = "<nil>"
                                                    }
                                                } catch {
                                                    errorMessage = String(describing: error)
                                                    showError = true
                                                }
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .padding(.trailing, 4)

                                        Button("Write") {
                                            Task {
                                                do {
                                                    // example: write a single byte 0x01
                                                    try await device.writeCharacteristic(char, data: Data([0x01]))
                                                } catch {
                                                    errorMessage = String(describing: error)
                                                    showError = true
                                                }
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .padding(.trailing, 4)

                                        // Subscribe toggle
                                        if subscriptions[char.uuid] == nil {
                                            Button("Subscribe") {
                                                let pub = device.subscribeToNotifications(for: char)
                                                let cancellable = pub.sink { completion in
                                                    if case .failure(let err) = completion {
                                                        errorMessage = String(describing: err)
                                                        showError = true
                                                    }
                                                } receiveValue: { data in
                                                    values[char.uuid] = data.map { String(format: "%02x", $0) }.joined()
                                                }
                                                subscriptions[char.uuid] = cancellable
                                            }
                                            .buttonStyle(.borderedProminent)
                                        } else {
                                            Button("Unsubscribe") {
                                                subscriptions[char.uuid]?.cancel()
                                                subscriptions.removeValue(forKey: char.uuid)
                                                device.setNotify(char, enabled: false)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            } else {
                                Text("No characteristics")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle(device.name ?? "Device")
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // If services not yet discovered, trigger discovery
            if device.services.isEmpty {
                device.discoverServices(nil)
            }
        }
    }
}

#Preview {
    // Note: preview uses placeholder; in real run use live device
    // Can't create a real CBPeripheral here; preview will be limited
    Text("Device Detail Preview")
}
