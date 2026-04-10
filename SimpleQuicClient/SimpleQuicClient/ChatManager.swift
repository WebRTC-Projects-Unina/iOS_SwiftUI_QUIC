import SwiftUI
import Network
import Observation

@Observable
class ChatManager {

    // NWConnectionGroup = the QUIC tunnel (one tunnel, multiple streams).
    private var group: NWConnectionGroup?

    // Bidirectional stream for chat messages.
    private var chatStream: NWConnection?

    // Bidirectional stream for presence/typing indicators.
    private var presenceStream: NWConnection?

    var username: String = ""

    var connectionState: String = "Disconnected"
    var isConnected: Bool = false
    var interfaceType: String = "—"
    var messages: [MessageItem] = []
    var typingUsers: Set<String> = []

    // One pending work item per sender — cancelled and replaced on each keystroke.
    @ObservationIgnored
    private var typingTimers: [String: DispatchWorkItem] = [:]

    func connect() {
        // ALPN token negotiated during the TLS handshake — both sides must agree.
        let options = NWProtocolQUIC.Options(alpn: ["quic-chat"])

        // Skip certificate verification (development only).
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, completion in
            completion(true)
        }, .main)

        // Idle timeout in milliseconds.
        options.idleTimeout = 300_000

        let parameters = NWParameters(quic: options)
        let endpoint = NWEndpoint.hostPort(host: "192.168.1.4", port: 8080)

        // NWMultiplexGroup + NWConnectionGroup set up the multiplexed QUIC tunnel.
        let descriptor = NWMultiplexGroup(to: endpoint)
        group = NWConnectionGroup(with: descriptor, using: parameters)

        // Called if the server opens a stream toward this client.
        // In QUIC either side can initiate streams — unlike plain TCP.
        group?.newConnectionHandler = { incomingStream in
            print("📥 Server opened a new stream toward the client")
            incomingStream.start(queue: .main)
        }

        // Tunnel-level state changes (Setup → Ready → Cancelled / Failed).
        group?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.connectionState = Self.formatState(state)
                self?.isConnected = (state == .ready)
                if case .ready = state { self?.openStreams() }
            }
        }

        group?.start(queue: .main)
    }

    private func openStreams() {
        guard let group else { return }

        // extract() creates an independent QUIC stream inside the existing tunnel.
        chatStream = group.extract()

        // Fires on every network path change (Wi-Fi <-> Cellular).
        chatStream?.pathUpdateHandler = { [weak self] (path: NWPath) in
            DispatchQueue.main.async {
                self?.interfaceType = Self.interfaceName(from: path)
            }
        }

        chatStream?.start(queue: .main)
        // First message — type "join" identifies this as the chat stream on the server.
        let joinMsg = ChatMessage(text: "\(username) has joined the chat!", type: "join", sender: username)
        if let data = try? JSONEncoder().encode(joinMsg) {
            chatStream?.send(content: data, completion: .contentProcessed({ _ in }))
        }
        startReceiving(on: chatStream!)

        presenceStream = group.extract()
        presenceStream?.start(queue: .main)
        startReceiving(on: presenceStream!)

        print("🔀 Multiple QUIC streams opened")
    }

    // Recursive receive loop — re-arms itself after each data chunk.
    private func startReceiving(on stream: NWConnection) {
        stream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data, let msg = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                DispatchQueue.main.async {
                    if msg.type == "presence" {
                        self?.handleTyping(from: msg.sender)
                    } else {
                        self?.messages.append(MessageItem(message: msg))
                    }
                }
            }
            if error == nil && !isComplete { self?.startReceiving(on: stream) }
        }
    }

    private func handleTyping(from sender: String) {
        typingTimers[sender]?.cancel()
        typingUsers.insert(sender)
        let work = DispatchWorkItem { [weak self] in
            self?.typingUsers.remove(sender)
            self?.typingTimers.removeValue(forKey: sender)
        }
        typingTimers[sender] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func send(_ text: String, type: String = "msg") {
        let msg = ChatMessage(text: text, type: type, sender: username)
        guard let data = try? JSONEncoder().encode(msg) else { return }
        if type == "msg" {
            messages.append(MessageItem(message: msg))
            chatStream?.send(content: data, completion: .contentProcessed({ _ in }))
        } else if type == "presence" {
            presenceStream?.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    private static func formatState(_ state: NWConnectionGroup.State) -> String {
        switch state {
        case .setup:              return "Setup"
        case .waiting(let error): return "Waiting — \(error.localizedDescription)"
        case .ready:              return "Ready"
        case .failed(let error):  return "Failed — \(error.localizedDescription)"
        case .cancelled:          return "Cancelled"
        }
    }

    private static func interfaceName(from path: NWPath) -> String {
        if path.usesInterfaceType(.wifi)          { return "Wi-Fi" }
        if path.usesInterfaceType(.cellular)      { return "Cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        if path.usesInterfaceType(.loopback)      { return "Loopback" }
        return "Unknown"
    }
}
