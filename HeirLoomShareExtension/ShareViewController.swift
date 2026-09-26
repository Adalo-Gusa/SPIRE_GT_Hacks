import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Custom Share Sheet View Controller for HeirLoom.
/// Extracts images, URLs, and plain text from Instagram or other apps,
/// then presents a Figma-styled HeirLoom SwiftUI card.
@objc(ShareViewController)
class ShareViewController: UIViewController {

    private var extractedImage: UIImage?
    private var extractedURL: URL?
    private var extractedCaption: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task {
            await extractPayload()
            await MainActor.run {
                presentSwiftUIInterface()
            }
        }
    }

    private func extractPayload() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            // Check text / caption
            if let text = item.attributedContentText?.string {
                extractedCaption = text
            }

            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // 1. Extract Image
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let image = await loadImage(from: provider) {
                        self.extractedImage = image
                    }
                }

                // 2. Extract Web URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        self.extractedURL = url
                        if extractedCaption.isEmpty {
                            extractedCaption = url.absoluteString
                        }
                    }
                }

                // 3. Extract Plain Text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider), extractedCaption.isEmpty {
                        self.extractedCaption = text
                    }
                }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let url = item as? URL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else if let image = item as? UIImage {
                    continuation.resume(returning: image)
                } else if let data = item as? Data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let text = item as? String, let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func presentSwiftUIInterface() {
        let rootView = ShareExtensionView(
            initialImage: extractedImage,
            initialURL: extractedURL,
            initialCaption: extractedCaption,
            onSave: { [weak self] payload, imageData in
                self?.saveAndComplete(payload: payload, imageData: imageData)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = UIColor(red: 0.82, green: 0.71, blue: 0.59, alpha: 0.96) // Warm board color
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func saveAndComplete(payload: SharedPostPayload, imageData: Data?) {
        do {
            try AppGroupStorage.shared.savePendingPost(payload: payload, imageData: imageData)
            print("[ShareExtension] Saved post to App Group: \(payload.id)")

            // Deep link into HeirLoom app so it opens immediately to the Family Feed
            if let deepLink = URL(string: "heirloom://shared-post") {
                openURL(deepLink)
            }

            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            print("[ShareExtension] Error saving post: \(error.localizedDescription)")
            extensionContext?.cancelRequest(withError: error)
        }
    }

    private func cancel() {
        let error = NSError(domain: "com.heirloom.share", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])
        extensionContext?.cancelRequest(withError: error)
    }

    @discardableResult
    private func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = responder?.next
        }
        return false
    }
}
