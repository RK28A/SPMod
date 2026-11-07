import UIKit
import UniformTypeIdentifiers

enum SPModBackupError: Error {
    case invalidFile
    case empty
}

enum SPModBackupHelper {
    private static let formatKey = "spmodBackupVersion"
    private static let valuesKey = "values"
    private static var pickerDelegate: DocumentPickerDelegate?

    static func makeBackupFile() throws -> URL {
        var values: [String: Any] = [:]
        for key in UserDefaults.spmodBackupKeys {
            if let value = UserDefaults.container.object(forKey: key), isSupported(value) {
                values[key] = value
            }
        }

        let root: [String: Any] = [
            formatKey: 1,
            "app": "SPMod",
            "version": EeveeSpotify.version,
            "date": Date(),
            valuesKey: values
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SPMod-Settings-\(formatter.string(from: Date())).plist")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportSettings() {
        do {
            let url = try makeBackupFile()
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            SPModAlertHelper.present(activity)
        }
        catch {
            SPModAlertHelper.info(title: "backup_export_failed".localized, message: error.localizedDescription)
        }
    }

    static func importSettings() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.propertyList, .xml, .data],
            asCopy: true
        )
        let delegate = DocumentPickerDelegate()
        pickerDelegate = delegate
        picker.delegate = delegate
        picker.allowsMultipleSelection = false
        SPModAlertHelper.present(picker)
    }

    static func restore(from url: URL) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard
            let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            root[formatKey] != nil,
            let values = root[valuesKey] as? [String: Any]
        else {
            throw SPModBackupError.invalidFile
        }

        let allowed = Set(UserDefaults.spmodBackupKeys)
        var restored = 0
        for (key, value) in values where allowed.contains(key) && isSupported(value) {
            UserDefaults.container.set(value, forKey: key)
            restored += 1
        }

        guard restored > 0 else {
            throw SPModBackupError.empty
        }
        return restored
    }

    private static func isSupported(_ value: Any) -> Bool {
        switch value {
        case is Data, is String, is NSNumber:
            return true
        case let array as [Any]:
            return array.allSatisfy { $0 is NSNumber || $0 is String }
        default:
            return false
        }
    }

    private class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            SPModBackupHelper.pickerDelegate = nil
            guard let url = urls.first else {
                return
            }
            do {
                let count = try SPModBackupHelper.restore(from: url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    SPModAlertHelper.askRestart(
                        message: "backup_import_success".localizeWithFormat(count)
                    )
                }
            }
            catch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    SPModAlertHelper.info(
                        title: "backup_import_failed".localized,
                        message: "backup_import_failed_description".localized
                    )
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            SPModBackupHelper.pickerDelegate = nil
        }
    }
}
