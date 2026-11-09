import Orion
import SwiftUI
import UIKit

class ProfileSettingsSectionHook: ClassHook<NSObject> {
    static let targetName = "ProfileSettingsSection"

    func numberOfRows() -> Int {
        return 2
    }

    func didSelectRow(_ row: Int) {
        if row == 1 {
            if let navigationController = WindowHelper.shared.findFirstViewController(
                "RootSettingsViewController"
            )?.navigationController {
                SPModulationEntry.open(from: navigationController)
            }
            return
        }

        orig.didSelectRow(row)
    }

    func cellForRow(_ row: Int) -> UITableViewCell {
        if row == 1 {
            let settingsTableCell = Dynamic.SPTSettingsTableViewCell
                .alloc(interface: SPTSettingsTableViewCell.self)
                .initWithStyle(3, reuseIdentifier: "SPModulation")
            
            let tableViewCell = Dynamic.convert(settingsTableCell, to: UITableViewCell.self)

            tableViewCell.accessoryView = type(
                of: Dynamic.SPTDisclosureAccessoryView
                    .alloc(interface: SPTDisclosureAccessoryView.self)
            )
            .disclosureAccessoryView()
            
            tableViewCell.textLabel?.text = "SPModulation"
            return tableViewCell
        }

        return orig.cellForRow(row)
    }
}

enum SPModulationEntry {
    private static let floatingButtonTag = 0x53504D44

    // The theme accent, or white when the accent is too dark to read on the bar.
    static var accentTextColor: UIColor {
        let accent = UIColor(spmodHex: UserDefaults.themeConfig.accentHex)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance < 0.14 ? .white : accent
    }

    static func open(from navigationController: UINavigationController) {
        SPModSettingsNavigator.navigationController = navigationController

        let controller = EeveeSettingsViewController(
            navigationController.view.bounds,
            settingsView: AnyView(EeveeSettingsView(navigationController: navigationController)),
            navigationTitle: "SPModulation"
        )

        let button = UIButton()
        button.setImage(
            BundleHelper.shared.uiImage("github").withRenderingMode(.alwaysOriginal),
            for: .normal
        )
        button.imageView?.contentMode = .scaleAspectFit
        button.contentHorizontalAlignment = .fill
        button.contentVerticalAlignment = .fill
        button.layer.cornerRadius = 13
        button.clipsToBounds = true
        button.addTarget(
            controller,
            action: #selector(controller.openRepositoryUrl(_:)),
            for: .touchUpInside
        )
        let item = UIBarButtonItem(customView: button)
        item.customView?.heightAnchor.constraint(equalToConstant: 26).isActive = true
        item.customView?.widthAnchor.constraint(equalToConstant: 26).isActive = true
        controller.navigationItem.rightBarButtonItem = item

        navigationController.pushViewController(controller, animated: true)
    }

    private static func containsSettingsList(_ viewController: UIViewController) -> Bool {
        if NSStringFromClass(type(of: viewController)).hasSuffix("SettingsListViewController") {
            return true
        }
        return viewController.children.contains(where: containsSettingsList)
    }

    private static func isRootSettingsPage(_ viewController: UIViewController, in navigationController: UINavigationController) -> Bool {
        var container: UIViewController? = viewController
        while let current = container, !navigationController.viewControllers.contains(where: { $0 === current }) {
            container = current.parent
        }
        guard let pageContainer = container else {
            return true
        }
        let firstSettingsPage = navigationController.viewControllers.first(where: containsSettingsList)
        return firstSettingsPage == nil || firstSettingsPage === pageContainer
    }

    static func attach(to viewController: UIViewController) {
        guard let navigationController = viewController.navigationController else {
            return
        }
        guard isRootSettingsPage(viewController, in: navigationController) else {
            return
        }

        if !navigationController.isNavigationBarHidden {
            if viewController.navigationItem.rightBarButtonItems?.contains(where: { $0.tag == floatingButtonTag }) == true {
                return
            }
            let item = UIBarButtonItem(
                title: "SPMod",
                style: .plain,
                target: SPModulationEntryTarget.shared,
                action: #selector(SPModulationEntryTarget.open(_:))
            )
            item.tag = floatingButtonTag
            item.tintColor = accentTextColor
            var items = viewController.navigationItem.rightBarButtonItems ?? []
            items.append(item)
            viewController.navigationItem.rightBarButtonItems = items
            return
        }

        guard viewController.view.viewWithTag(floatingButtonTag) == nil else {
            return
        }

        let button = UIButton(type: .system)
        button.tag = floatingButtonTag
        button.setTitle("  SPModulation  ", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = UIColor(spmodHex: UserDefaults.themeConfig.accentHex)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(SPModulationEntryTarget.shared, action: #selector(SPModulationEntryTarget.open(_:)), for: .touchUpInside)

        viewController.view.addSubview(button)
        viewController.view.bringSubviewToFront(button)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 36),
            button.trailingAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }
}

final class SPModulationEntryTarget: NSObject {
    static let shared = SPModulationEntryTarget()

    @objc func open(_ sender: Any) {
        var responder: UIResponder? = sender as? UIView
        while let current = responder {
            if let viewController = current as? UIViewController, let navigationController = viewController.navigationController {
                SPModulationEntry.open(from: navigationController)
                return
            }
            responder = current.next
        }
        if let navigationController = WindowHelper.shared.findFirstViewController("SettingsListViewController")?.navigationController {
            SPModulationEntry.open(from: navigationController)
            return
        }
        SPModulationShortcut.presentModally()
    }

    @objc func shortcut(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SPModulationShortcut.presentModally()
    }

    @objc func close(_ sender: Any) {
        SPModSettingsNavigator.navigationController?.dismiss(animated: true)
    }
}

class SettingsListViewControllerHook: ClassHook<UIViewController> {
    static let targetName = "Settings_PlatformImpl.SettingsListViewController"

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        SPModulationEntry.attach(to: target)
    }
}

enum SPModulationShortcut {
    private static var installedWindows = NSHashTable<UIWindow>.weakObjects()
    private static var observer: NSObjectProtocol?

    static func start() {
        DispatchQueue.main.async {
            install()
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                install()
            }
        }
    }

    private static func install() {
        guard let window = WindowHelper.shared.window, !installedWindows.contains(window) else {
            return
        }
        let recognizer = UILongPressGestureRecognizer(
            target: SPModulationEntryTarget.shared,
            action: #selector(SPModulationEntryTarget.shortcut(_:))
        )
        recognizer.numberOfTouchesRequired = 3
        recognizer.minimumPressDuration = 0.8
        recognizer.cancelsTouchesInView = false
        window.addGestureRecognizer(recognizer)
        installedWindows.add(window)
    }

    static func presentModally() {
        let navigationController = UINavigationController()
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.overrideUserInterfaceStyle = .dark
        navigationController.modalPresentationStyle = .fullScreen

        SPModSettingsNavigator.navigationController = navigationController

        let controller = EeveeSettingsViewController(
            UIScreen.main.bounds,
            settingsView: AnyView(EeveeSettingsView(navigationController: navigationController)),
            navigationTitle: "SPModulation"
        )
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: SPModulationEntryTarget.shared,
            action: #selector(SPModulationEntryTarget.close(_:))
        )
        navigationController.viewControllers = [controller]
        SPModAlertHelper.present(navigationController)
    }
}
