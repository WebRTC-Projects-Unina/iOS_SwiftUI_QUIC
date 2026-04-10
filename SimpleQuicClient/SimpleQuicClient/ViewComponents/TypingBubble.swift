import SwiftUI

// Shown when a remote participant is typing — disappears after 3 s of inactivity.
struct TypingBubble: View {
    let username: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(username)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("···")
                    .padding(10)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(10)
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal)
    }
}
