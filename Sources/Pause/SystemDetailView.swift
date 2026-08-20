import SwiftUI

/// Circular gauge, like Stats.app's ring, but drawn plainly with SwiftUI shapes.
struct RingGaugeView: View {
    let fraction: Double
    var lineWidth: CGFloat = 10
    var showLabel: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(gradientColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showLabel {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private var gradientColor: AngularGradient {
        AngularGradient(colors: [.green, .yellow, .orange, .red], center: .center)
    }
}

/// Full system memory breakdown: ring, history graph, segmented bar, and top processes.
struct SystemDetailView: View {
    @ObservedObject var model: AppListModel
    let stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                RingGaugeView(fraction: stats.usedFraction)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory Pressure").font(.system(size: 13, weight: .semibold))
                    Text(pressureLabel)
                        .font(.caption)
                        .foregroundStyle(pressureColor)
                    Text("\(MenuView.fmt(stats.usedBytes)) of \(MenuView.fmt(stats.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("USAGE HISTORY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                SparklineView(history: model.systemHistory, color: .blue, lineWidth: 1.5)
                    .frame(height: 70)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BREAKDOWN")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                segmentedBar
                legendRow("App", .blue, stats.appBytes)
                legendRow("Wired", .orange, stats.wiredBytes)
                legendRow("Compressed", .pink, stats.compressedBytes)
                legendRow("Free", .gray, stats.freeBytes)
                legendRow("Swap Used", .purple, stats.swapUsedBytes)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("TOP PROCESSES")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                ForEach(model.entries.prefix(6)) { entry in
                    HStack {
                        if let icon = entry.icon {
                            Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                        }
                        Text(entry.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(MenuView.fmt(entry.resident))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var segmentedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                segment(.blue, stats.appBytes, geo.size.width)
                segment(.orange, stats.wiredBytes, geo.size.width)
                segment(.pink, stats.compressedBytes, geo.size.width)
                segment(.gray, stats.freeBytes, geo.size.width)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    private func segment(_ color: Color, _ bytes: UInt64, _ totalWidth: CGFloat) -> some View {
        let fraction = stats.totalBytes == 0 ? 0 : Double(bytes) / Double(stats.totalBytes)
        return color.frame(width: max(0, totalWidth * CGFloat(fraction)))
    }

    private func legendRow(_ label: String, _ color: Color, _ bytes: UInt64) -> some View {
        HStack {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2)
            Spacer()
            Text(MenuView.fmt(bytes)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var pressureLabel: String {
        switch stats.usedFraction {
        case ..<0.6: return "Normal"
        case ..<0.85: return "Warning"
        default: return "Critical"
        }
    }

    private var pressureColor: Color {
        switch stats.usedFraction {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }
}
