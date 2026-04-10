import Foundation
import Network
import Security

// JSON message exchanged over QUIC streams.
struct ChatMessage: Codable {
    let text: String
    let type: String   // "msg", "presence" or "join"
    let sender: String // name of the Sender
}

// Registries of active streams per type, all accessed on the main queue.
var activeChatStreams: [NWConnection] = []
var activePresenceStreams: [NWConnection] = []

// Server Configuration

let port: NWEndpoint.Port = 8080

// NWProtocolQUIC.Options configures the QUIC protocol layer.
let quicOptions = NWProtocolQUIC.Options(alpn: ["quic-chat"])

// Idle timeout in milliseconds. QUIC closes the connection if no data is exchanged within this window.
quicOptions.idleTimeout = 300_000

// QUIC mandates TLS 1.3.
sec_protocol_options_set_min_tls_protocol_version(quicOptions.securityProtocolOptions, .TLSv13)

if let identity = loadIdentity() {
    sec_protocol_options_set_local_identity(quicOptions.securityProtocolOptions, identity)
    print("TLS identity loaded")
} else {
    print("Server starting without a certificate — QUIC will fail")
}

let parameters = NWParameters(quic: quicOptions)

// NWListener accepts incoming QUIC connections on the specified port.
let listener = try! NWListener(using: parameters, on: port)

// MARK: - Connection Handling

// Fires when a client establishes a QUIC tunnel (the multiplexed connection).
listener.newConnectionGroupHandler = { group in
    print("🚇 QUIC tunnel established")

    // Fires for each stream the client opens within the tunnel.
    group.newConnectionHandler = { connection in

        var clientName = "Unknown"
        var isChatStream = false
        var isPresenceStream = false

        // Read the QUIC stream ID once the stream reaches Ready state.
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                print("Stream ready - QUIC Stream ID: \(streamID(of: connection))")
            }
        }

        connection.start(queue: .main)

        // Recursive receive loop
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data, let msg = try? JSONDecoder().decode(ChatMessage.self, from: data) {
                    if clientName == "Unknown" { clientName = msg.sender }
                    print("📩 \(msg.sender) [\(msg.type)]: \(msg.text)")

                    switch msg.type {
                    case "join":
                        isChatStream = true
                        activeChatStreams.append(connection)
                        print("👥 Active clients: \(activeChatStreams.count)")
                        broadcastMessage(data, excluding: connection)
                    case "msg":
                        broadcastMessage(data, excluding: connection)
                    case "presence":
                        if !isPresenceStream {
                            isPresenceStream = true
                            activePresenceStreams.append(connection)
                        }
                        broadcastPresence(data, excluding: connection)
                    default:
                        break
                    }
                }

                if error == nil && !isComplete {
                    receive()
                } else {
                    if isChatStream {
                        activeChatStreams.removeAll { $0 === connection }
                        print("🔌 \(clientName) disconnected — \(activeChatStreams.count) remaining")
                    } else if isPresenceStream {
                        activePresenceStreams.removeAll { $0 === connection }
                    }
                }
            }
        }

        receive()
    }

    group.start(queue: .main)
}

// Utility functions

// The TLS identity (certificate + private key) is required for the TLS 1.3 handshake in QUIC.
func loadIdentity() -> sec_identity_t? {
    let path = "/Users/vincenzogerelli/Desktop/identity.p12"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        print("❌ Certificate file not found at \(path)")
        return nil
    }

    let importOptions: [String: Any] = [kSecImportExportPassphrase as String: "12345678"]
    var rawItems: CFArray?
    let status = SecPKCS12Import(data as CFData, importOptions as CFDictionary, &rawItems)

    guard status == errSecSuccess,
          let items = rawItems as? [[String: Any]],
          let identity = items.first?[kSecImportItemIdentity as String]
    else {
        print("❌ Failed to import identity — wrong password or corrupted file")
        return nil
    }

    return sec_identity_create(identity as! SecIdentity)
}

// Broadcasts message data to every registered chat stream except the sender.
func broadcastMessage(_ data: Data, excluding sender: NWConnection) {
    for stream in activeChatStreams where stream !== sender {
        stream.send(content: data, completion: .contentProcessed { _ in })
    }
}

// Broadcasts presence data to every registered presence stream except the sender.
func broadcastPresence(_ data: Data, excluding sender: NWConnection) {
    for stream in activePresenceStreams where stream !== sender {
        stream.send(content: data, completion: .contentProcessed { _ in })
    }
}

// Returns the QUIC stream identifier from NWProtocolQUIC.Metadata.
func streamID(of connection: NWConnection) -> String {
    guard let metadata = connection.metadata(definition: NWProtocolQUIC.definition)
            as? NWProtocolQUIC.Metadata
    else { return "unavailable" }
    return "\(metadata.streamIdentifier)"
}


// Start

listener.start(queue: .main)
print("Simple multiplexed QUIC server listening on port \(port)…")
RunLoop.main.run()
