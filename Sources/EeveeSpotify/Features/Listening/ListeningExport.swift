import UIKit
import UniformTypeIdentifiers

enum ListeningExportFormat {
    case json
    case csv
}

enum ListeningExport {
    private static var pickerDelegate: PickerDelegate?

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func export(_ format: ListeningExportFormat) {
        let records = ListeningStore.shared.allRecords()
        do {
            let url: URL
            switch format {
            case .json:
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(records)
                url = FileManager.default.temporaryDirectory.appendingPathComponent("SPMod-Listening-\(timestamp()).json")
                try data.write(to: url, options: .atomic)
            case .csv:
                let iso = ISO8601DateFormatter()
                var lines = ["date,title,artist,album,track_id,listened_seconds,duration_seconds,completed"]
                for record in records {
                    lines.append([
                        iso.string(from: record.start),
                        csvField(record.title),
                        csvField(record.artist),
                        csvField(record.album),
                        csvField(record.trackId),
                        String(Int(record.listened.rounded())),
                        String(Int(record.duration.rounded())),
                        record.completed ? "1" : "0"
                    ].joined(separator: ","))
                }
                url = FileManager.default.temporaryDirectory.appendingPathComponent("SPMod-Listening-\(timestamp()).csv")
                try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
            }
            SPModAlertHelper.present(UIActivityViewController(activityItems: [url], applicationActivities: nil))
        }
        catch {
            SPModAlertHelper.info(title: "backup_export_failed".localized, message: error.localizedDescription)
        }
    }

    static func importData() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .commaSeparatedText, .plainText, .data],
            asCopy: true
        )
        let delegate = PickerDelegate()
        pickerDelegate = delegate
        picker.delegate = delegate
        picker.allowsMultipleSelection = false
        SPModAlertHelper.present(picker)
    }

    static func parse(_ data: Data) -> [PlayRecord]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let records = try? decoder.decode([PlayRecord].self, from: data) {
            return records
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        var records: [PlayRecord] = []
        for line in text.components(separatedBy: .newlines).dropFirst() where !line.isEmpty {
            let fields = parseCSVLine(line)
            guard fields.count >= 8, let date = iso.date(from: fields[0]) else {
                continue
            }
            records.append(PlayRecord(
                id: UUID(),
                trackId: fields[4],
                title: fields[1],
                artist: fields[2],
                album: fields[3],
                start: date,
                listened: TimeInterval(fields[5]) ?? 0,
                duration: TimeInterval(fields[6]) ?? 0,
                completed: fields[7] == "1"
            ))
        }
        return records.isEmpty ? nil : records
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = Array(line)
        var index = 0
        while index < iterator.count {
            let character = iterator[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < iterator.count && iterator[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                    }
                    else {
                        inQuotes = false
                    }
                }
                else {
                    current.append(character)
                }
            }
            else if character == "\"" {
                inQuotes = true
            }
            else if character == "," {
                fields.append(current)
                current = ""
            }
            else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current)
        iterator.removeAll()
        return fields
    }

    private class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            ListeningExport.pickerDelegate = nil
            guard let url = urls.first else {
                return
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard
                let data = try? Data(contentsOf: url),
                let records = ListeningExport.parse(data)
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    SPModAlertHelper.info(
                        title: "backup_import_failed".localized,
                        message: "listening_import_invalid".localized
                    )
                }
                return
            }
            let added = ListeningStore.shared.merge(records)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                SPModAlertHelper.info(
                    title: "listening_import_done".localized,
                    message: "listening_import_count".localizeWithFormat(added)
                )
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            ListeningExport.pickerDelegate = nil
        }
    }
}
