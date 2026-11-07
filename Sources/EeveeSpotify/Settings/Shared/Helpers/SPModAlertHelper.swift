import UIKit

struct SPModAlertStep {
    var title: String
    var message: String
    var confirmTitle: String
    var isDestructive: Bool = false
}

enum SPModAlertHelper {
    private static func topViewController() -> UIViewController? {
        guard var top = WindowHelper.shared.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    static func present(_ viewController: UIViewController) {
        DispatchQueue.main.async {
            guard let top = topViewController() else {
                return
            }
            if let popover = viewController.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            top.present(viewController, animated: true)
        }
    }

    static func confirm(_ steps: [SPModAlertStep], onConfirm: @escaping () -> Void) {
        guard let step = steps.first else {
            onConfirm()
            return
        }

        let alert = UIAlertController(title: step.title, message: step.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(
            title: step.confirmTitle,
            style: step.isDestructive ? .destructive : .default
        ) { _ in
            confirm(Array(steps.dropFirst()), onConfirm: onConfirm)
        })
        present(alert)
    }

    static func askRestart(message: String = "restart_prompt_message".localized) {
        let alert = UIAlertController(
            title: "restart_prompt_title".localized,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "later".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "restart_now".localized, style: .default) { _ in
            exitApplication()
        })
        present(alert)
    }

    static func info(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert)
    }
}
