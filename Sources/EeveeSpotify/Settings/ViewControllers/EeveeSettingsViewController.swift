import SwiftUI
import UIKit 

class EeveeSettingsViewController: SPTPageViewController {
    let frame: CGRect
    let settingsView: AnyView
    
    init(_ frame: CGRect, settingsView: AnyView, navigationTitle: String) {
        self.frame = frame
        self.settingsView = settingsView
        super.init(nibName: nil, bundle: nil)
        
        title = navigationTitle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let background = UIColor(spmodHex: UserDefaults.themeConfig.backgroundHex)
        view.backgroundColor = background

        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.view.frame = frame
        hostingController.view.backgroundColor = background

        view.addSubview(hostingController.view)
        addChild(hostingController)
        hostingController.didMove(toParent: self)
    }
    
    @objc func openRepositoryUrl(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/RK28A/SPMod")!)
    }
}
