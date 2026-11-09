import Orion
import UIKit
import ObjectiveC.runtime

struct PlayerRedesignGroup: HookGroup {}

enum PlayerRedesign {
    static let backgroundTag = 0x53504D47
    static let controlsGlassTag = 0x53504D48
    static let tintTag = 0x53504D49

    // Tint colour comes from the active theme accent, so changing the theme
    // changes the colour of the glass transparency.
    static var themeTint: UIColor {
        UIColor(spmodHex: UserDefaults.themeConfig.accentHex)
    }

    static var tintAlpha: CGFloat {
        CGFloat(UserDefaults.glassOpacity)
    }

    // UIGlassEffect (iOS 26+) via runtime so the build never hard-depends on it.
    // Falls back to an ultra-thin material blur on older systems.
    static func makeGlassEffect() -> UIVisualEffect {
        if let cls = NSClassFromString("UIGlassEffect") as? UIVisualEffect.Type {
            let effect = cls.init()
            if effect.responds(to: Selector(("setInteractive:"))) {
                effect.setValue(true, forKey: "interactive")
            }
            return effect
        }
        return UIBlurEffect(style: .systemUltraThinMaterialDark)
    }

    private static func tintOverlay(in effectView: UIVisualEffectView) {
        let overlay: UIView
        if let existing = effectView.contentView.viewWithTag(tintTag) {
            overlay = existing
        } else {
            overlay = UIView()
            overlay.tag = tintTag
            overlay.isUserInteractionEnabled = false
            overlay.translatesAutoresizingMaskIntoConstraints = false
            effectView.contentView.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor)
            ])
        }
        overlay.backgroundColor = themeTint.withAlphaComponent(tintAlpha)
    }

    static func installBackground(in view: UIView) {
        let effectView: UIVisualEffectView
        if let existing = view.viewWithTag(backgroundTag) as? UIVisualEffectView {
            effectView = existing
        } else {
            effectView = UIVisualEffectView(effect: makeGlassEffect())
            effectView.tag = backgroundTag
            effectView.isUserInteractionEnabled = false
            effectView.alpha = 0.0
            effectView.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(effectView, at: 0)
            NSLayoutConstraint.activate([
                effectView.topAnchor.constraint(equalTo: view.topAnchor),
                effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            UIView.animate(withDuration: 0.35) { effectView.alpha = 1.0 }
        }
        tintOverlay(in: effectView)
    }

    // Rounds the largest near-square image view found in the tree (the album
    // artwork). Entirely best-effort: if nothing qualifies it does nothing.
    static func roundCoverArt(in root: UIView) {
        var best: UIImageView?
        var bestArea: CGFloat = 0

        func walk(_ view: UIView) {
            for sub in view.subviews {
                if let image = sub as? UIImageView {
                    let size = image.bounds.size
                    let area = size.width * size.height
                    if size.width >= 140,
                       abs(size.width - size.height) < 30,
                       area > bestArea {
                        best = image
                        bestArea = area
                    }
                }
                walk(sub)
            }
        }
        walk(root)

        guard let artwork = best else { return }
        let radius = min(26, artwork.bounds.width * 0.09)
        if artwork.layer.cornerRadius != radius {
            artwork.layer.cornerRadius = radius
            artwork.layer.cornerCurve = .continuous
            artwork.clipsToBounds = true
        }
    }

    // Finds the horizontal band of playback buttons and floats a rounded glass
    // card behind it. Identified by a container whose direct subviews are mostly
    // UIControls — no fragile class-name matching.
    static func installControlsGlass(in root: UIView) {
        func buttonContainer(_ view: UIView) -> UIView? {
            for sub in view.subviews {
                let buttons = sub.subviews.filter { $0 is UIControl }
                if buttons.count >= 3,
                   sub.bounds.width > root.bounds.width * 0.5,
                   sub.bounds.height < 160,
                   sub.viewWithTag(controlsGlassTag) == nil {
                    return sub
                }
                if let found = buttonContainer(sub) {
                    return found
                }
            }
            return nil
        }

        guard let container = buttonContainer(root) else { return }

        let glass = UIVisualEffectView(effect: makeGlassEffect())
        glass.tag = controlsGlassTag
        glass.isUserInteractionEnabled = false
        glass.layer.cornerRadius = min(28, container.bounds.height * 0.5)
        glass.layer.cornerCurve = .continuous
        glass.clipsToBounds = true
        glass.translatesAutoresizingMaskIntoConstraints = false

        container.insertSubview(glass, at: 0)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: container.topAnchor, constant: -6),
            glass.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 6),
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: -10),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 10)
        ])
        tintOverlay(in: glass)
    }
}

class NPVLiquidGlassHook: ClassHook<UIViewController> {
    typealias Group = PlayerRedesignGroup
    static let targetName = "NowPlaying_ScrollImpl.NPVScrollViewController"

    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        guard UserDefaults.playerLiquidGlass, let view = target.view else { return }
        PlayerRedesign.installBackground(in: view)
    }

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        guard UserDefaults.playerLiquidGlass, let view = target.view else { return }
        PlayerRedesign.installBackground(in: view)
        PlayerRedesign.roundCoverArt(in: view)
        PlayerRedesign.installControlsGlass(in: view)
    }
}

func activatePlayerRedesign() {
    guard UserDefaults.playerLiquidGlass else { return }

    guard let cls = findTweakClass(NPVLiquidGlassHook.targetName) else {
        SPModDiagnostics.record("[Redesign] NPVScrollViewController not found; skipping")
        return
    }
    guard class_getInstanceMethod(cls, Selector(("viewDidLayoutSubviews"))) != nil else {
        SPModDiagnostics.record("[Redesign] no viewDidLayoutSubviews; skipping")
        return
    }

    PlayerRedesignGroup().activate()
    SPModDiagnostics.record("[Redesign] player liquid glass activated")
}
