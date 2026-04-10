import SwiftUI

// Compact card showing live QUIC connection diagnostics.
struct ConnectionInfoPanel: View {
    var vm: ChatManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connection Info")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                InfoRow(label: "State",     value: vm.connectionState)
                InfoRow(label: "Interface", value: vm.interfaceType)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// Single label/value row used inside ConnectionInfoPanel.
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
    }
}
