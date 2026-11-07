import UIKit

struct WindowHelper {
    static let shared = WindowHelper()
    
    var window: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first ?? UIApplication.shared.windows.first
    }
    
    var rootViewController: UIViewController? {
        window?.rootViewController
    }
    
    private init() { }

    func present(_ viewController: UIViewController) {
        guard var presenter = rootViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        presenter.present(viewController, animated: true)
    }
    
    func findFirstSubview(_ regex: String, in view: UIView) -> UIView? {
        for subview in view.subviews {
            if NSStringFromClass(type(of: subview)) ~= regex {
                return subview
            }
            if let found = findFirstSubview(regex, in: subview) {
                return found
            }
        }
        
        return nil
    }

    func findFirstViewController(_ regex: String) -> UIViewController? {
        guard let rootView = self.rootViewController?.view else { return nil }
        var result: UIViewController?
        
        func searchViews(_ view: UIView) {
            if let viewController = self.viewController(for: view) {
                if NSStringFromClass(type(of: viewController)) ~= regex {
                    result = viewController
                    return
                }    
            }

            for subview in view.subviews {
                searchViews(subview) 
            }
        }
        
        searchViews(rootView)
        return result
    }
    
    func dismissCurrentViewController() {
        rootViewController?.dismiss(animated: true)
    }

    func overrideUserInterfaceStyle(_ style: UIUserInterfaceStyle) {
        window?.overrideUserInterfaceStyle = style
    }

    func viewController(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            responder = nextResponder
        }
        return nil
    }
}
