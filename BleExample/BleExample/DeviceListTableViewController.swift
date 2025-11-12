import UIKit
import BluetoothManager
import Combine

class DeviceListTableViewController: UITableViewController {
    enum ListType {
        case discovered, connecting, connected
    }

    private let listType: ListType
    private var devices: [BluetoothDevice] = []
    private var disposables = Set<AnyCancellable>()

    init(listType: ListType) {
        self.listType = listType
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        observeManager()
    }

    private func observeManager() {
        let mgr = BluetoothManager.shared
        switch listType {
        case .discovered:
            mgr.$discoveredDevices.sink { [weak self] devs in
                self?.devices = devs
                DispatchQueue.main.async { self?.tableView.reloadData() }
            }.store(in: &disposables)
        case .connecting:
            mgr.$connectingDevices.sink { [weak self] devs in
                self?.devices = devs
                DispatchQueue.main.async { self?.tableView.reloadData() }
            }.store(in: &disposables)
        case .connected:
            mgr.$connectedDevices.sink { [weak self] devs in
                self?.devices = devs
                DispatchQueue.main.async { self?.tableView.reloadData() }
            }.store(in: &disposables)
        }
    }

    // MARK: - Table
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        devices.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let device = devices[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = device.name ?? "Unknown"
        content.secondaryText = device.uuidString
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let device = devices[indexPath.row]
        let detail = UIKitDeviceDetailViewController(device: device)
        navigationController?.pushViewController(detail, animated: true)
    }
}
