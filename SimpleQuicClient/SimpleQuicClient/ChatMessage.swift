import Foundation

// JSON message exchanged over QUIC streams.
struct ChatMessage: Codable {
    let text: String
    let type: String   // "msg", "presence", or "join"
    let sender: String
}

// Wraps a ChatMessage with a stable UUID for SwiftUI list identity.
struct MessageItem: Identifiable {
    let id = UUID()
    let message: ChatMessage
}
