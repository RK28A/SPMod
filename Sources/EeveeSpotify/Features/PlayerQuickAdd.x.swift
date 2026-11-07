import Orion
import UIKit

struct PlayerButtonsGroup: HookGroup { }

class NPVQuickAddButtonHook: ClassHook<UIViewController> {
    typealias Group = PlayerButtonsGroup
    static let targetName = "NowPlaying_ScrollImpl.NPVScrollViewController"

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        PlayerQuickAddButton.install(in: target)
    }
}

final class PlayerQuickAddButton: UIButton {
    static let viewTag = 0x53504D51

    static func install(in viewController: UIViewController) {
        guard let view = viewController.view, view.viewWithTag(viewTag) == nil else {
            return
        }

        let button = PlayerQuickAddButton(type: .custom)
        button.tag = viewTag
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor(white: 0, alpha: 0.35)
        button.layer.cornerRadius = 20
        button.tintColor = .white
        button.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            for: .normal
        )
        button.accessibilityLabel = "quick_add".localized
        button.addTarget(button, action: #selector(tapped), for: .touchUpInside)
        button.addGestureRecognizer(UILongPressGestureRecognizer(target: button, action: #selector(longPressed(_:))))

        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -40)
        ])
    }

    @objc private func tapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if QuickAddStore.destination == nil {
            Self.chooseDestination()
            return
        }
        QuickAddStore.addCurrentTrack()
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let destination = QuickAddStore.destination?.name ?? "vault_no_folder".localized
        let sheet = UIAlertController(
            title: "quick_add".localized,
            message: "quick_add_destination_is".localizeWithFormat(destination),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "quick_add_change".localized, style: .default) { _ in
            Self.chooseDestination()
        })
        if QuickAddStore.pinned != nil {
            sheet.addAction(UIAlertAction(title: "quick_add_unpin".localized, style: .destructive) { _ in
                QuickAddStore.pinned = nil
            })
        }
        sheet.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
        SPModAlertHelper.present(sheet)
    }

    static func chooseDestination() {
        Task {
            do {
                let playlists = try await SpotifyWebAPI.editablePlaylists()
                await MainActor.run {
                    let sheet = UIAlertController(
                        title: "playlist_choose_destination".localized,
                        message: nil,
                        preferredStyle: .actionSheet
                    )
                    for playlist in playlists.prefix(40) {
                        sheet.addAction(UIAlertAction(title: playlist.name, style: .default) { _ in
                            QuickAddStore.pinned = QuickAddStore.Target(id: playlist.id, name: playlist.name)
                            QuickAddStore.addCurrentTrack()
                        })
                    }
                    sheet.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
                    SPModAlertHelper.present(sheet)
                }
            }
            catch {
                ToastHelper.show(error.localizedDescription)
            }
        }
    }
}
