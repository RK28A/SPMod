import Foundation
import SwiftUI
import libroot

class BundleHelper {
    private let bundleName = "EeveeSpotify"
    
    private let bundle: Bundle
    private let enBundle: Bundle
    
    static let shared = BundleHelper()
    
    private init() {
        let bundle = Bundle(
            path: Bundle.main.path(
                forResource: bundleName,
                ofType: "bundle"
            )
            ?? jbRootPath("/Library/Application Support/\(bundleName).bundle")
        ) ?? Bundle.main
        
        self.bundle = bundle
        enBundle = bundle.path(forResource: "en", ofType: "lproj").flatMap { Bundle(path: $0) } ?? bundle
    }
    
    func uiImage(_ name: String) -> UIImage {
        guard
            let path = self.bundle.path(forResource: name, ofType: "png"),
            let image = UIImage(contentsOfFile: path)
        else {
            return UIImage()
        }
        return image
    }
    
    func localizedString(_ key: String) -> String {
        let value = bundle.localizedString(forKey: key, value: "No translation", table: nil)
        
        if value != "No translation" {
            return value
        }
        
        return enBundle.localizedString(forKey: key, value: nil, table: nil)
    }
    
    func resolveConfiguration() throws -> ResolveConfiguration {
        guard let url = self.bundle.url(forResource: "resolveconfiguration", withExtension: "bnk") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try ResolveConfiguration(serializedBytes: try Data(contentsOf: url))
    }
}
