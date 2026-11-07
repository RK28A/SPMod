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
        button.addTarget(
            controller,
            action: #selector(controller.openRepositoryUrl(_:)),
            for: .touchUpInside
        )
        let item = UIBarButtonItem(customView: button)
        item.customView?.heightAnchor.constraint(equalToConstant: 22).isActive = true
        item.customView?.widthAnchor.constraint(equalToConstant: 22).isActive = true
        controller.navigationItem.rightBarButtonItem = item

        navigationController.pushViewController(controller, animated: true)
    }

    static func attach(to viewController: UIViewController) {
        guard let navigationController = viewController.navigationController else {
            return
        }
        let settingsClass: AnyClass = type(of: viewController)
        guard navigationController.viewControllers.first(where: { $0.isKind(of: settingsClass) }) === viewController else {
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
        }
    }
}

class SettingsListViewControllerHook: ClassHook<UIViewController> {
    static let targetName = "Settings_PlatformImpl.SettingsListViewController"

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        SPModulationEntry.attach(to: target)
    }
}
