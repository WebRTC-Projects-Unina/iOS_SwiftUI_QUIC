import SwiftUI

// Chat bubble — own messages on the right, others on the left, join messages centered.
struct MessageBubble: View {
    let message: ChatMessage
    let localUsername: String

    private var isOwn: Bool { message.sender == localUsername }

    var body: some View {
        if message.type == "join" {
            // Join messages are displayed as a centered annotation.
            Text(message.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        } else {
            HStack {
                if isOwn { Spacer(minLength: 40) }
                VStack(alignment: isOwn ? .trailing : .leading, spacing: 2) {
                    Text(isOwn ? "You" : message.sender)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(message.text)
                        .padding(10)
                        .background(isOwn ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .cornerRadius(10)
                }
                if !isOwn { Spacer(minLength: 40) }
            }
            .padding(.horizontal)
        }
    }
}
