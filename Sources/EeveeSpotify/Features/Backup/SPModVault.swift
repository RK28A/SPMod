import Foundation
import Security
import UIKit
import UniformTypeIdentifiers

enum SPModVault {
    static let schemaVersion = 1
    static let formatName = "spmod-backup"
    static let fileName = "SPMod-Backup.json"
    static let previousFileName = "SPMod-Backup-previous.json"

    private static let folderBookmarkKey = "spmodVaultFolderBookmark"
    private static let autoBackupKey = "spmodVaultAutoBackup"
    private static let lastBackupKey = "spmodVaultLastBackup"
    private static let installMarkerKey = "spmodVaultInstalled"
    private static let restorePromptKey = "spmodVaultRestorePromptDone"
    private static let keychainService = "SPModVault"
    private static let keychainAccount = "settings"
    private static let queue = DispatchQueue(label: "spmod.vault")
    private static var observers: [NSObjectProtocol] = []
    private static var pickerDelegate: PickerDelegate?

    static var autoBackupEnabled: Bool {
        get { UserDefaults.container.object(forKey: autoBackupKey) as? Bool ?? true }
        set { UserDefaults.container.set(newValue, forKey: autoBackupKey) }
    }

    static var lastBackup: Date? {
        get { UserDefaults.container.object(forKey: lastBackupKey) as? Date }
        set { UserDefaults.container.set(newValue, forKey: lastBackupKey) }
    }

    static var hasFolder: Bool {
        UserDefaults.container.data(forKey: folderBookmarkKey) != nil
    }

    static var folderName: String? {
        resolveFolder()?.lastPathComponent
    }

    static func start() {
        DispatchQueue.main.async {
            restoreAfterReinstallIfNeeded()

            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                autoBackup()
            })
        }
    }

    // MARK: Encoding

    private static func encodeValue(_ value: Any) -> [String: Any]? {
        switch value {
        case let data as Data:
            return ["t": "data", "v": data.base64EncodedString()]
        case let string as String:
            return ["t": "string", "v": string]
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return ["t": "bool", "v": number.boolValue]
            }
            if CFNumberIsFloatType(number) {
                return ["t": "double", "v": number.doubleValue]
            }
            return ["t": "int", "v": number.int64Value]
        case let date as Date:
            return ["t": "date", "v": date.timeIntervalSince1970]
        case let array as [Any]:
            let items = array.compactMap(encodeValue)
            return items.count == array.count ? ["t": "array", "v": items] : nil
        case let dictionary as [String: Any]:
            var items: [String: Any] = [:]
            for (key, item) in dictionary {
                guard let encoded = encodeValue(item) else {
                    return nil
                }
                items[key] = encoded
            }
            return ["t": "dict", "v": items]
        default:
            return nil
        }
    }

    private static func decodeValue(_ wrapper: Any?) -> Any? {
        guard let wrapper = wrapper as? [String: Any], let type = wrapper["t"] as? String else {
            return nil
        }
        let value = wrapper["v"]
        switch type {
        case "data":
            return (value as? String).flatMap { Data(base64Encoded: $0) }
        case "string":
            return value as? String
        case "bool":
            return (value as? NSNumber)?.boolValue ?? (value as? Bool)
        case "int":
            return (value as? NSNumber)?.int64Value
        case "double":
            return (value as? NSNumber)?.doubleValue
        case "date":
            return (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        case "array":
            guard let items = value as? [Any] else {
                return nil
            }
            let decoded = items.compactMap(decodeValue)
            return decoded.count == items.count ? decoded : nil
        case "dict":
            guard let items = value as? [String: Any] else {
                return nil
            }
            var decoded: [String: Any] = [:]
            for (key, item) in items {
                if let value = decodeValue(item) {
                    decoded[key] = value
                }
            }
            return decoded
        default:
            return nil
        }
    }

    private static func settingsPayload() -> [String: Any] {
        var settings: [String: Any] = [:]
        for key in UserDefaults.spmodBackupKeys {
            if let value = UserDefaults.container.object(forKey: key), let encoded = encodeValue(value) {
                settings[key] = encoded
            }
        }
        return settings
    }

    private static func recordPayload(_ record: PlayRecord) -> [String: Any] {
        [
            "id": record.id.uuidString,
            "trackId": record.trackId,
            "title": record.title,
            "artist": record.artist,
            "album": record.album,
            "start": record.start.timeIntervalSince1970,
            "listened": record.listened,
            "duration": record.duration,
            "completed": record.completed
        ]
    }

    static func makeBackupData(includeListening: Bool = true) throws -> Data {
        var root: [String: Any] = [
            "format": formatName,
            "schema": schemaVersion,
            "appVersion": EeveeSpotify.version,
            "createdAt": Date().timeIntervalSince1970,
            "settings": settingsPayload()
        ]
        if includeListening {
            root["listening"] = ListeningStore.shared.allRecords().map(recordPayload)
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    // MARK: Decoding

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private static func parseRecord(_ value: Any) -> PlayRecord? {
        guard let item = value as? [String: Any] else {
            return nil
        }
        let title = item["title"] as? String ?? ""
        guard
            !title.isEmpty,
            let start = date(item["start"] ?? item["startedAt"] ?? item["started_at"])
        else {
            return nil
        }
        let listened = number(item["listened"] ?? item["listened_s"]) ?? 0
        let duration = number(item["duration"] ?? item["duration_s"]) ?? 0
        let completed = (item["completed"] as? NSNumber)?.boolValue
            ?? (duration > 0 && listened >= duration * 0.85)

        return PlayRecord(
            id: (item["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
            trackId: item["trackId"] as? String ?? item["track_id"] as? String ?? "",
            title: title,
            artist: item["artist"] as? String ?? "",
            album: item["album"] as? String ?? "",
            start: start,
            listened: listened,
            duration: duration,
            completed: completed
        )
    }

    private static func migrate(_ root: [String: Any]) -> [String: Any] {
        root
    }

    @discardableResult
    static func restore(from data: Data, includeSettings: Bool = true) throws -> (settings: Int, plays: Int) {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["format"] as? String == formatName
        else {
            throw SPModBackupError.invalidFile
        }
        let root = migrate(object)

        var restoredSettings = 0
        if includeSettings, let settings = root["settings"] as? [String: Any] {
            for (key, wrapper) in settings where key != folderBookmarkKey {
                if let value = decodeValue(wrapper) {
                    UserDefaults.container.set(value, forKey: key)
                    restoredSettings += 1
                }
            }
        }

        var restoredPlays = 0
        if let listening = root["listening"] as? [Any] {
            let records = listening.compactMap(parseRecord)
            restoredPlays = ListeningStore.shared.merge(records)
        }

        if restoredSettings == 0 && restoredPlays == 0 && (root["settings"] == nil) {
            throw SPModBackupError.empty
        }
        return (restoredSettings, restoredPlays)
    }

    // MARK: Keychain

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    private static func saveToKeychain(_ data: Data) {
        let query = keychainQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func loadFromKeychain() -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    // MARK: Folder

    private static func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.container.data(forKey: folderBookmarkKey) else {
            return nil
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, url.startAccessingSecurityScopedResource() {
            if let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.container.set(refreshed, forKey: folderBookmarkKey)
            }
            url.stopAccessingSecurityScopedResource()
        }
        return url
    }

    private static func writeToFolder(_ data: Data) -> Bool {
        guard let folder = resolveFolder() else {
            return false
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                folder.stopAccessingSecurityScopedResource()
            }
        }

        let target = folder.appendingPathComponent(fileName)
        let previous = folder.appendingPathComponent(previousFileName)
        var success = false
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.copyItem(at: url, to: previous)
            }
            success = (try? data.write(to: url, options: .atomic)) != nil
        }
        return success && coordinationError == nil
    }

    static func chooseFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        let delegate = PickerDelegate(mode: .folder)
        pickerDelegate = delegate
        picker.delegate = delegate
        SPModAlertHelper.present(picker)
    }

    static func chooseRestoreFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data], asCopy: true)
        let delegate = PickerDelegate(mode: .restore)
        pickerDelegate = delegate
        picker.delegate = delegate
        SPModAlertHelper.present(picker)
    }

    // MARK: Backup

    private final class BackgroundTaskBox {
        var identifier = UIBackgroundTaskIdentifier.invalid

        func end() {
            guard identifier != .invalid else {
                return
            }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }

    static func backupNow(completion: ((Bool) -> Void)? = nil) {
        let box = BackgroundTaskBox()
        box.identifier = UIApplication.shared.beginBackgroundTask(withName: "SPModVault") {
            box.end()
        }

        queue.async {
            let success = performBackup()
            DispatchQueue.main.async {
                completion?(success)
                box.end()
            }
        }
    }

    private static func performBackup() -> Bool {
        var success = false
        if let settingsData = try? makeBackupData(includeListening: false) {
            saveToKeychain(settingsData)
            success = true
        }
        if hasFolder, let fullData = try? makeBackupData(includeListening: true) {
            success = writeToFolder(fullData)
        }
        if success {
            lastBackup = Date()
        }
        return success
    }

    static func autoBackup() {
        guard autoBackupEnabled else {
            return
        }
        if let last = lastBackup, Date().timeIntervalSince(last) < 5 * 60 {
            return
        }
        backupNow()
    }

    // MARK: Restore after reinstall

    private static func restoreAfterReinstallIfNeeded() {
        let defaults = UserDefaults.container
        guard !defaults.bool(forKey: installMarkerKey) else {
            return
        }
        defaults.set(true, forKey: installMarkerKey)

        let hasExistingSettings = UserDefaults.spmodBackupKeys.contains { defaults.object(forKey: $0) != nil }
        let hasRecords = !ListeningStore.shared.allRecords().isEmpty
        guard !hasExistingSettings && !hasRecords else {
            return
        }

        if let data = loadFromKeychain(), (try? restore(from: data)) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                ToastHelper.show("vault_settings_restored".localized)
            }
        }

        guard !defaults.bool(forKey: restorePromptKey) else {
            return
        }
        defaults.set(true, forKey: restorePromptKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            let alert = UIAlertController(
                title: "vault_restore_prompt_title".localized,
                message: "vault_restore_prompt_message".localized,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "later".localized, style: .cancel))
            alert.addAction(UIAlertAction(title: "vault_restore_choose".localized, style: .default) { _ in
                chooseRestoreFile()
            })
            SPModAlertHelper.present(alert)
        }
    }

    private enum PickerMode {
        case folder
        case restore
    }

    private class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        let mode: PickerMode

        init(mode: PickerMode) {
            self.mode = mode
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            SPModVault.pickerDelegate = nil
            guard let url = urls.first else {
                return
            }

            switch mode {
            case .folder:
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
                    SPModAlertHelper.info(title: "vault_folder_failed".localized, message: "")
                    return
                }
                UserDefaults.container.set(bookmark, forKey: SPModVault.folderBookmarkKey)
                NotificationCenter.default.post(name: SPModVault.didChangeNotification, object: nil)

                let restoreURL = url.appendingPathComponent(SPModVault.fileName)
                if ListeningStore.shared.allRecords().isEmpty,
                   let data = try? Data(contentsOf: restoreURL),
                   let result = try? SPModVault.restore(from: data) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        SPModAlertHelper.askRestart(
                            message: "vault_restore_success".localizeWithFormat(result.settings, result.plays)
                        )
                    }
                    return
                }

                SPModVault.backupNow { success in
                    ToastHelper.show(success ? "vault_backup_done".localized : "vault_backup_failed".localized)
                }

            case .restore:
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let result = try SPModVault.restore(from: Data(contentsOf: url))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        SPModAlertHelper.askRestart(
                            message: "vault_restore_success".localizeWithFormat(result.settings, result.plays)
                        )
                    }
                }
                catch {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        SPModAlertHelper.info(
                            title: "backup_import_failed".localized,
                            message: "vault_restore_invalid".localized
                        )
                    }
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            SPModVault.pickerDelegate = nil
        }
    }

    static let didChangeNotification = Notification.Name("SPModVaultChanged")
}
