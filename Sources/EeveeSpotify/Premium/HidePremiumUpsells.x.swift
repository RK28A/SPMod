import Orion
import UIKit

struct PremiumUpsellGroup: HookGroup { }

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
