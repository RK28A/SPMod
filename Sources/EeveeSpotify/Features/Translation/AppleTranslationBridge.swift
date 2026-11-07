import Foundation
import SwiftUI
import UIKit
#if canImport(Translation)
import Translation

@available(iOS 18.0, *)
final class AppleTranslationBridge {
    static let shared = AppleTranslationBridge()

    private let exclusive = DispatchSemaphore(value: 1)
    private var host: UIHostingController<AppleTranslationHostView>?
    private let model = AppleTranslationModel()

    func translate(_ lines: [String], target: String) -> [String]? {
        guard !Thread.isMainThread, exclusive.wait(timeout: .now() + 20) == .success else {
            return nil
        }
        defer { exclusive.signal() }

        let semaphore = DispatchSemaphore(value: 0)
        var output: [String]? = nil

        DispatchQueue.main.async {
            guard self.installHostIfNeeded() else {
                semaphore.signal()
                return
            }
            self.model.request(lines: lines, target: target) { result in
                output = result
                semaphore.signal()
            }
        }

        guard semaphore.wait(timeout: .now() + 15) == .success else {
            DispatchQueue.main.async {
                self.model.cancel()
            }
            return nil
        }
        return output
    }

    private func installHostIfNeeded() -> Bool {
        if let host = host, host.view.window != nil {
            return true
        }
        host?.view.removeFromSuperview()
        host?.removeFromParent()
        host = nil

        guard let root = WindowHelper.shared.rootViewController else {
            return false
        }
        let controller = UIHostingController(rootView: AppleTranslationHostView(model: model))
        controller.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        controller.view.alpha = 0.011
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        host = controller
        return true
    }
}

@available(iOS 18.0, *)
final class AppleTranslationModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private var pendingLines: [String] = []
    private var completion: (([String]?) -> Void)?

    func request(lines: [String], target: String, completion: @escaping ([String]?) -> Void) {
        self.completion?(nil)
        pendingLines = lines
        self.completion = completion

        let targetLanguage = Locale.Language(identifier: target)
        if configuration?.target == targetLanguage {
            configuration?.invalidate()
        }
        else {
            configuration = TranslationSession.Configuration(source: nil, target: targetLanguage)
        }
    }

    func cancel() {
        completion = nil
        pendingLines = []
    }

    @MainActor
    func run(_ session: TranslationSession) async {
        let lines = pendingLines
        guard let completion = completion else {
            return
        }
        self.completion = nil
        pendingLines = []

        let requests = lines.enumerated().map { index, line in
            TranslationSession.Request(sourceText: line, clientIdentifier: String(index))
        }

        do {
            let responses = try await session.translations(from: requests)
            var output = lines
            for response in responses {
                if let identifier = response.clientIdentifier,
                   let index = Int(identifier),
                   output.indices.contains(index) {
                    output[index] = response.targetText.trimmingCharacters(in: .whitespaces)
                }
            }
            completion(output)
        }
        catch {
            completion(nil)
        }
    }
}

@available(iOS 18.0, *)
struct AppleTranslationHostView: View {
    @ObservedObject var model: AppleTranslationModel

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(model.configuration) { session in
                await model.run(session)
            }
    }
}
#endif

enum OnDeviceTranslation {
    static var isAvailable: Bool {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            return true
        }
        #endif
        return false
    }

    static func translate(_ lines: [String], target: String) -> [String]? {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            return AppleTranslationBridge.shared.translate(lines, target: target)
        }
        #endif
        return nil
    }
}
