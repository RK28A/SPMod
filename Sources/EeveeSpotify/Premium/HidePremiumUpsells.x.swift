import Orion
import UIKit

struct PremiumUpsellGroup: HookGroup { }

enum PremiumUpsellHider {
    static func mentionsPremium(_ text: String?) -> Bool {
        guard let text = text else {
            return false
        }
        return text.range(of: "premium", options: .caseInsensitive) != nil
    }

    static func isPremiumTab(_ view: UIView) -> Bool {
        if mentionsPremium(view.accessibilityLabel) {
            return true
        }
        var stack: [UIView] = [view]
        var visited = 0
        while let current = stack.popLast(), visited < 60 {
            visited += 1
            if let label = current as? UILabel, mentionsPremium(label.text) {
                return true
            }
            stack.append(contentsOf: current.subviews)
        }
        return false
    }
}

class PremiumStatusRowSettingsHook: ClassHook<NSObject> {
    typealias Group = PremiumUpsellGroup
    static let targetName = "SPTEncorePremiumStatusRowSettings"

    func uiView() -> UIView {
        let view = orig.uiView()
        let container = UIView()
        container.isHidden = true
        container.isUserInteractionEnabled = false
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 0).isActive = true
        _ = view
        return container
    }
}

class SelfLoadingUpsellBannerHook: ClassHook<UIView> {
    typealias Group = PremiumUpsellGroup
    static let targetName = "Upsells_UIKit.SelfLoadingUpsellBannerUIView"

    func didMoveToWindow() {
        orig.didMoveToWindow()
        target.isHidden = true
        target.alpha = 0
    }

    func layoutSubviews() {
        orig.layoutSubviews()
        if !target.isHidden {
            target.isHidden = true
        }
    }
}

class PremiumTabBarItemHook: ClassHook<UIView> {
    typealias Group = PremiumUpsellGroup
    static let targetName = "NavigationUI_TabBarImpl.TabBarItemElementView"

    func layoutSubviews() {
        orig.layoutSubviews()
        if !target.isHidden && PremiumUpsellHider.isPremiumTab(target) {
            target.isHidden = true
        }
    }

    func didMoveToWindow() {
        orig.didMoveToWindow()
        if PremiumUpsellHider.isPremiumTab(target) {
            target.isHidden = true
        }
    }
}
