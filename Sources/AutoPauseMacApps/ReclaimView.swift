import SwiftUI

/// "Local Model Mode": free a chosen amount of RAM in one click, then put it all back.
struct ReclaimView: View {
    @ObservedObject var model: AppListModel
    let onDone: () -> Void

    @State private var targetGB: Double = 8

    private var targetBytes: UInt64 { UInt64(targetGB * 1_073_741_824) }
    private var available: UInt64 { model.reclaimableBytes }
    private var achievable: Bool { available >= targetBytes }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 24)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Up Memory").font(.system(size: 15, weight: .semibold))
                    Text("Make room for a local model").font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Target").font(.caption)
                    Spacer()
                    Text(String(format: "%.0f GB", targetGB))
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
                Slider(value: $targetGB, in: 1...16, step: 1)
                HStack {
                    Image(systemName: achievable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(achievable ? .green : .orange)
                    Text(achievable
                         ? "About \(MenuView.fmt(available)) can be freed right now."
                         : "Only about \(MenuView.fmt(available)) is available to free.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Text("Freezes background apps and services, heaviest first, until it reaches your target. Your frontmost app and anything protected are never touched.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.reclaimSession.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.blue)
                    Text("\(model.reclaimSession.count) items frozen by the last run")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore") {
                        model.restoreReclaimSession()
                        onDone()
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onDone)
                Button("Free \(String(format: "%.0f", targetGB)) GB") {
                    model.reclaim(targetBytes: targetBytes)
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
