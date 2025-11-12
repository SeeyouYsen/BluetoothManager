import UIKit
import BluetoothManager
import Combine

class UIKitDeviceDetailViewController: UIViewController {
    private let device: BluetoothDevice
    private var disposables = Set<AnyCancellable>()

    private let nameLabel = UILabel()
    private let uuidLabel = UILabel()
    private let connectButton = UIButton(type: .system)

    init(device: BluetoothDevice) {
        self.device = device
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        bind()
    }

    private func setupUI() {
        nameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        uuidLabel.font = .systemFont(ofSize: 12)
        uuidLabel.textColor = .secondaryLabel
        connectButton.setTitle("Connect", for: .normal)
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [nameLabel, uuidLabel, connectButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func bind() {
        nameLabel.text = device.name ?? "Unknown"
        uuidLabel.text = device.uuidString

        // Observe connectedDevices to update button title
        BluetoothManager.shared.$connectedDevices.sink { [weak self] devs in
            guard let self = self else { return }
            let isConnected = devs.contains(where: { $0.uuidString == self.device.uuidString })
            DispatchQueue.main.async {
                self.connectButton.setTitle(isConnected ? "Disconnect" : "Connect", for: .normal)
            }
        }.store(in: &disposables)
    }

    @objc private func connectTapped() {
        let mgr = BluetoothManager.shared
        let isConnected = mgr.connectedDevices.contains(where: { $0.uuidString == device.uuidString })
        if isConnected {
            mgr.disconnect(peripheral: device.peripheral)
            return
        }
        // Use non-async connect to initiate connection immediately
        mgr.connect(peripheral: device.peripheral)
    }
}
