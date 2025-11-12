import SwiftUI
import UIKit

/// A UIViewControllerRepresentable that hosts a UINavigationController with the UIKit demo root.
struct UIKitContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let root = UIKitHomeViewController()
        let nav = UINavigationController(rootViewController: root)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
