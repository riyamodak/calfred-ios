import Messages
import SwiftUI
import CalendarDomain

final class MessagesViewController: MSMessagesAppViewController {
    private let model = MessagesModel()
    private var host: UIHostingController<MessagesHarnessView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.insert = { [weak self] snapshot, url in
            guard let conversation = self?.activeConversation else { throw MessagesProbeError.noConversation }
            let layout = MSMessageTemplateLayout()
            layout.caption = snapshot.event.displayTitle
            layout.subcaption = snapshot.event.time.probeDescription
            layout.trailingCaption = "Independent calendar copy"
            let message = MSMessage()
            message.url = url
            message.layout = layout
            message.summaryText = snapshot.event.displayTitle
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                conversation.insert(message) { error in
                    if error != nil { continuation.resume(throwing: MessagesProbeError.insertionFailed) }
                    else { continuation.resume() }
                }
            }
        }
        model.openSetup = { [weak self] url in
            guard let context = self?.extensionContext else { return false }
            return await withCheckedContinuation { continuation in
                context.open(url) { continuation.resume(returning: $0) }
            }
        }
        let host = UIHostingController(rootView: MessagesHarnessView(model: model))
        self.host = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        Task { await model.activate(messageURL: conversation.selectedMessage?.url) }
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        requestPresentationStyle(.expanded)
        Task { await model.activate(messageURL: message.url) }
    }
}

enum MessagesProbeError: LocalizedError {
    case noConversation, insertionFailed, noDestination, changedDestination
    var errorDescription: String? {
        switch self {
        case .noConversation: return "Open Calendar Share inside an iMessage conversation."
        case .insertionFailed: return "Card insertion failed. Retry uses the same snapshot and share ID."
        case .noDestination: return "Choose a calendar."
        case .changedDestination: return "That calendar is no longer writable or the account changed. Choose a calendar again."
        }
    }
}
