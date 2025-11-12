import UIKit
import BluetoothManager
import Combine

class UIKitHomeViewController: UITabBarController {
    private var discoveredVC: DeviceListTableViewController!
    private var connectingVC: DeviceListTableViewController!
    private var connectedVC: DeviceListTableViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BLE Devices (UIKit)"
        setupTabs()
        setupNavigationItems()
    }

    private func setupTabs() {
        discoveredVC = DeviceListTableViewController(listType: .discovered)
        discoveredVC.title = "Discovered"
        discoveredVC.tabBarItem = UITabBarItem(title: "Discovered", image: UIImage(systemName: "magnifyingglass"), tag: 0)

        connectingVC = DeviceListTableViewController(listType: .connecting)
        connectingVC.title = "Connecting"
        connectingVC.tabBarItem = UITabBarItem(title: "Connecting", image: UIImage(systemName: "bolt.horizontal"), tag: 1)

        connectedVC = DeviceListTableViewController(listType: .connected)
        connectedVC.title = "Connected"
        connectedVC.tabBarItem = UITabBarItem(title: "Connected", image: UIImage(systemName: "link"), tag: 2)

        viewControllers = [UINavigationController(rootViewController: discoveredVC), UINavigationController(rootViewController: connectingVC), UINavigationController(rootViewController: connectedVC)]
    }

    private func setupNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Status", style: .plain, target: self, action: #selector(showStatus))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: BluetoothManager.shared.isScanning ? "Stop" : "Scan", style: .done, target: self, action: #selector(toggleScan))

        // Observe scanning state to update button title
        BluetoothManager.shared.$isScanning.sink { [weak self] scanning in
            DispatchQueue.main.async {
                self?.navigationItem.rightBarButtonItem?.title = scanning ? "Stop" : "Scan"
            }
        }.store(in: &disposables)
    }

    @objc private func showStatus() {
        let mgr = BluetoothManager.shared
        let msg = mgr.isPoweredOn ? (mgr.isScanning ? "Bluetooth On — Scanning" : "Bluetooth On — Idle") : "Bluetooth Off"
        let ac = UIAlertController(title: "Status", message: msg, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(ac, animated: true)
    }

    @objc private func toggleScan() {
        let mgr = BluetoothManager.shared
        if mgr.isScanning {
            mgr.stopScan()
        } else if mgr.isPoweredOn {
            mgr.startScan()
        } else {
            let ac = UIAlertController(title: "Bluetooth Off", message: "Bluetooth is off or unavailable.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        }
    }

    // Keep Combine disposables
    private var disposables = Set<AnyCancellable>()
}
