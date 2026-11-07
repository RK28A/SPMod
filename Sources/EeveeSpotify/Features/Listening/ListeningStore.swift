import Foundation
import UIKit

final class ListeningStore {
    static let shared = ListeningStore()
    static let didChangeNotification = Notification.Name("SPModListeningChanged")

    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "spmod.listening.io")
    private let artworkMemory = NSCache<NSString, UIImage>()
    private var records: [PlayRecord] = []
    private var loaded = false
    private var saveScheduled = false

    static var directory: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = support.appendingPathComponent("SPMod", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var artworkDirectory: URL? {
        guard let base = directory else {
            return nil
        }
        let url = base.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var fileURL: URL? {
        ListeningStore.directory?.appendingPathComponent("listening.json")
    }

    static func artworkKey(album: String, artist: String) -> String {
        let raw = "\(artist.lowercased())|\(album.lowercased())"
        return String(raw.hashValueStable)
    }

    private func ensureLoaded() {
        guard !loaded else {
            return
        }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let url = fileURL,
            let data = try? Data(contentsOf: url),
            let decoded = try? decoder.decode([PlayRecord].self, from: data)
        else {
            return
        }
        records = decoded.sorted { $0.start < $1.start }
    }

    private func scheduleSave() {
        guard !saveScheduled else {
            return
        }
        saveScheduled = true
        ioQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.saveNow()
        }
    }

    private func saveNow() {
        lock.lock()
        saveScheduled = false
        let snapshot = records
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let url = fileURL, let data = try? encoder.encode(snapshot) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ListeningStore.didChangeNotification, object: nil)
        }
    }

    func allRecords() -> [PlayRecord] {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        return records
    }

    func add(_ record: PlayRecord) {
        lock.lock()
        ensureLoaded()
        if let last = records.last,
           last.trackKey == record.trackKey,
           abs(last.start.timeIntervalSince(record.start)) < 2 {
            lock.unlock()
            return
        }
        records.append(record)
        if records.count > 1, records[records.count - 2].start > record.start {
            records.sort { $0.start < $1.start }
        }
        scheduleSave()
        lock.unlock()
        notify()
    }

    @discardableResult
    func merge(_ incoming: [PlayRecord]) -> Int {
        lock.lock()
        ensureLoaded()
        let ids = Set(records.map(\.id))
        let signatures = Set(records.map { "\($0.trackKey)|\(Int($0.start.timeIntervalSince1970))" })
        let fresh = incoming.filter {
            !ids.contains($0.id) && !signatures.contains("\($0.trackKey)|\(Int($0.start.timeIntervalSince1970))")
        }
        records.append(contentsOf: fresh)
        records.sort { $0.start < $1.start }
        scheduleSave()
        lock.unlock()
        notify()
        return fresh.count
    }

    func delete(ids: Set<UUID>) {
        lock.lock()
        ensureLoaded()
        records.removeAll { ids.contains($0.id) }
        scheduleSave()
        lock.unlock()
        notify()
    }

    func delete(in interval: DateInterval) {
        lock.lock()
        ensureLoaded()
        records.removeAll { interval.contains($0.start) }
        scheduleSave()
        lock.unlock()
        notify()
    }

    func deleteAll() {
        lock.lock()
        ensureLoaded()
        records.removeAll()
        scheduleSave()
        lock.unlock()
        artworkMemory.removeAllObjects()
        if let directory = ListeningStore.artworkDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        notify()
    }

    func hasArtwork(for key: String) -> Bool {
        guard let url = ListeningStore.artworkDirectory?.appendingPathComponent("\(key).jpg") else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func storeArtwork(_ image: UIImage, for key: String) {
        guard
            let url = ListeningStore.artworkDirectory?.appendingPathComponent("\(key).jpg"),
            let data = image.jpegData(compressionQuality: 0.8)
        else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    func artwork(for key: String) -> UIImage? {
        if let cached = artworkMemory.object(forKey: key as NSString) {
            return cached
        }
        guard
            let url = ListeningStore.artworkDirectory?.appendingPathComponent("\(key).jpg"),
            let image = UIImage(contentsOfFile: url.path)
        else {
            return nil
        }
        artworkMemory.setObject(image, forKey: key as NSString)
        return image
    }
}

extension String {
    var hashValueStable: UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}
