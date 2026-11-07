import Orion
import UIKit
import SwiftUI

struct DarkPopUps: HookGroup { }

private var popUpContainerViewController: String {
    switch EeveeSpotify.hookTarget {
    case .lastAvailableiOS14: return "SPTEncorePopUpContainer"
    default: return "EncoreConsumerMobile_Wrappers.PopUpPresentableContainer"
    }
}

class EncoreLabelHook: ClassHook<UIView> {
    typealias Group = DarkPopUps
    static let targetName = "SPTEncoreLabel"

    func intrinsicContentSize() -> CGSize {
        if let viewController = WindowHelper.shared.viewController(for: target),
            NSStringFromClass(type(of: viewController)) == popUpContainerViewController
        {
            if let subview = target.subviews.first {
                let label = Dynamic.convert(subview, to: UILabel.self)

                if !label.hasParent(matching: "Primary") {
                    label.textColor = .white
                }
            }
        }

        return orig.intrinsicContentSize()
    }
}

class SPTEncorePopUpContainerHook: ClassHook<UIViewController> {
    typealias Group = DarkPopUps
    static let targetName = popUpContainerViewController
    
    func containedView() -> SPTEncorePopUpDialog {
        return orig.containedView()
    }
    
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        containedView().uiView().backgroundColor = UIColor(Color(hex: "#242424"))
    }
}
