import AppKit
import Network

/// Receives playback from the NotchIsland browser extension over a loopback-only WebSocket,
/// and sends commands back to the tab that is playing. One connection per browser.
final class BrowserBridgeSource: MediaSource {
    static let port: UInt16 = 47_823

    let id = "browser"
    var onChange: (() -> Void)?
    private(set) var snapshot: PlaybackSnapshot? {
        didSet { if snapshot != oldValue { onChange?() } }
    }

    private struct Tab: Decodable {
        let tabId: Int
        let title: String
        let artist: String
        let album: String?
        let artwork: String?
        let duration: Double
        let position: Double
        let playing: Bool
        let site: String
        let canSeek: Bool
        let canSkip: Bool
        let updatedAt: Double
    }

    private struct Call: Decodable {
        let tabId: Int
        let site: String
        let title: String
    }

    private struct Message: Decodable {
        let type: String
        let browser: String?
        let tabs: [Tab]?
        let calls: [Call]?
    }

    private struct Browser {
        let connection: NWConnection
        var name = "Browser"
        var tabs: [Tab] = []
    }

    /// Called once when a video call starts in a browser tab (Meet, Zoom, Teams, ...).
    var onCallStarted: ((_ site: String) -> Void)?
    /// Last time each call was reported. A call missing for a while counts as new when it returns;
    /// a brief gap (the extension reconnecting) doesn't announce it again.
    private var callsLastSeen: [String: Date] = [:]
    private let callForgetAfter: TimeInterval = 60

    private var listener: NWListener?
    private var browsers: [ObjectIdentifier: Browser] = [:]
    private var selected: (browser: ObjectIdentifier, tabId: Int)?
    /// When each playing tab started playing, so two playing tabs don't trade places on every update.
    private var playingSince: [String: Date] = [:]
    private var artworkCache: [String: NSImage] = [:]
    private var artworkLoading: Set<String> = []

    init() {
        start()
    }

    // MARK: - Server

    private func start() {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        // Only browser extensions may connect, not web pages.
        ws.setClientRequestHandler(.main) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let allowed = ["chrome-extension://", "moz-extension://", "safari-web-extension://"]
                .contains { origin.hasPrefix($0) }
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject,
                                                subprotocol: nil, additionalHeaders: nil)
        }

        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { NSLog("NotchIsland bridge failed: %@", "\(error)") }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            NSLog("NotchIsland bridge could not start: %@", "\(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        browsers[key] = Browser(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(key)
            default: break
            }
        }
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            let key = ObjectIdentifier(connection)
            if let data,
               let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                   as? NWProtocolWebSocket.Metadata,
               meta.opcode == .text {
                handle(data, from: key)
            }
            if error == nil {
                receive(on: connection)
            } else {
                connection.cancel()
                drop(key)
            }
        }
    }

    private func drop(_ key: ObjectIdentifier) {
        guard browsers.removeValue(forKey: key) != nil else { return }
        recompute()
    }

    private func handle(_ data: Data, from key: ObjectIdentifier) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data),
              message.type == "state" else { return }
        let browserName = message.browser ?? "Browser"
        browsers[key]?.name = browserName
        browsers[key]?.tabs = message.tabs ?? []
        noteCalls(message.calls ?? [], in: browserName)
        recompute()
    }

    private func noteCalls(_ calls: [Call], in browserName: String) {
        let now = Date()
        for call in calls {
            let id = "\(browserName)-\(call.tabId)"
            let isNew = callsLastSeen[id].map { now.timeIntervalSince($0) > callForgetAfter } ?? true
            callsLastSeen[id] = now
            if isNew { onCallStarted?(call.site) }
        }
    }

    // MARK: - Snapshot

    /// The tab that most recently *started* playing wins; otherwise keep showing the last one.
    private func recompute() {
        let all = browsers.flatMap { key, browser in browser.tabs.map { (key, browser.name, $0) } }

        let now = Date()
        var since: [String: Date] = [:]
        for (key, _, tab) in all where tab.playing {
            let id = Self.tabKey(key, tab.tabId)
            since[id] = playingSince[id] ?? now
        }
        playingSince = since

        let pick = all.filter { $0.2.playing }.max { a, b in
            since[Self.tabKey(a.0, a.2.tabId)]! < since[Self.tabKey(b.0, b.2.tabId)]!
        }
            ?? all.first { $0.0 == selected?.browser && $0.2.tabId == selected?.tabId }
            ?? all.max { $0.2.updatedAt < $1.2.updatedAt }

        guard let (key, browserName, tab) = pick else {
            selected = nil
            snapshot = nil
            return
        }
        selected = (key, tab.tabId)
        if let url = tab.artwork { loadArtwork(url) }

        snapshot = PlaybackSnapshot(
            sourceID: id,
            appName: "\(tab.site) · \(browserName)",
            title: tab.title,
            artist: tab.artist,
            album: tab.album ?? "",
            artwork: tab.artwork.flatMap { artworkCache[$0] },
            artworkID: tab.artwork,
            duration: tab.duration,
            elapsed: tab.position,
            timestamp: Date(timeIntervalSince1970: tab.updatedAt / 1000),
            isPlaying: tab.playing,
            canSeek: tab.canSeek,
            canSkip: tab.canSkip
        )
    }

    private static func tabKey(_ browser: ObjectIdentifier, _ tabId: Int) -> String {
        "\(browser.hashValue)-\(tabId)"
    }

    private func loadArtwork(_ urlString: String) {
        guard artworkCache[urlString] == nil, !artworkLoading.contains(urlString),
              let url = URL(string: urlString), ["http", "https", "data"].contains(url.scheme) else { return }
        artworkLoading.insert(urlString)
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                artworkLoading.remove(urlString)
                if let image {
                    artworkCache[urlString] = image
                    recompute()
                }
            }
        }.resume()
    }

    // MARK: - Commands

    func send(_ command: MediaCommand) {
        guard let selected, let connection = browsers[selected.browser]?.connection else { return }
        var payload: [String: Any] = ["type": "command", "tabId": selected.tabId]
        switch command {
        case .togglePlayPause: payload["action"] = "toggle"
        case .next: payload["action"] = "next"
        case .previous: payload["action"] = "previous"
        case .seek(let time):
            payload["action"] = "seek"
            payload["time"] = time
        case .focus: payload["action"] = "focus"
        }

        snapshot = snapshot?.applying(command)

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "command", metadata: [meta])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}
