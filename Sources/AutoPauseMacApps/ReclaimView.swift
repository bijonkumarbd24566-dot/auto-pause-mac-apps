import SwiftUI

/// Free Up Memory — review exactly what will be paused, then confirm.
///
/// Deliberately never acts on a click alone. An earlier version froze whatever it judged
/// heaviest the moment you pressed the button, including a screen recorder mid-capture, with
/// no chance to object. Nothing here is paused until you have seen the list and pressed the
/// confirm button.
struct ReclaimView: View {
    @ObservedObject var model: AppListModel
    let onDone: () -> Void

    /// Apps ticked for pausing. Everything starts ticked; unticking is how you opt out.
    @State private var selected: Set<String> = []
    @State private var candidates: [AppEntry] = []
    @State private var rememberOptOuts = true

    /// Apps that are plausibly capturing or presenting right now. These start UNTICKED:
    /// pausing a screen recorder mid-capture destroys the recording, and pausing a call
    /// drops it — neither is something to do by default.
    private static let captureApps: Set<String> = [
        "com.apple.QuickTimePlayerX", "com.obsproject.obs-studio", "com.telestream.screenflow",
        "com.telestream.screenflow10", "net.telestream.screenflow", "com.getcleanshot.desktop",
        "com.loom.desktop", "com.screen.studio", "com.techsmith.camtasia",
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.google.meet",
        "com.cisco.webexmeetingsapp", "com.hnc.Discord", "com.tinyspeck.slackmacgap",
        "com.apple.FaceTime", "com.riverside.desktop", "com.descript.beachcube"
    ]

    private func isCaptureApp(_ entry: AppEntry) -> Bool {
        guard let id = entry.bundleID else { return false }
        return Self.captureApps.contains(id)
    }

    private var chosen: [AppEntry] { candidates.filter { selected.contains($0.id) } }
    private var freeing: UInt64 { chosen.reduce(0) { $0 + $1.resident } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if candidates.isEmpty {
                Text("No apps available to pause right now.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 26)
            } else {
                selectAllBar
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(candidates) { entry in
                            row(entry)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear {
            candidates = model.reclaimCandidates
            // Everything ticked except likely recording/calling apps.
            selected = Set(candidates.filter { !isCaptureApp($0) }.map(\.id))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Image(systemName: "cpu.fill").font(.system(size: 20)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Free Up Memory").font(.system(size: 14, weight: .semibold))
                    Text("Review what gets paused, then confirm")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9)).foregroundStyle(.green)
                Text("Untick anything you're using. Recording and call apps start unticked. Nothing is paused until you press the button.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private var selectAllBar: some View {
        HStack {
            Button(selected.count == candidates.count ? "Untick all" : "Tick all") {
                selected = selected.count == candidates.count ? [] : Set(candidates.map(\.id))
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.blue)
            Spacer()
            Text("\(selected.count) of \(candidates.count) selected")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13)
        .padding(.top, 7)
    }

    private func row(_ entry: AppEntry) -> some View {
        let isOn = selected.contains(entry.id)
        return Button {
            if isOn { selected.remove(entry.id) } else { selected.insert(entry.id) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? .teal : .secondary)
                if let icon = entry.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        .opacity(isOn ? 1 : 0.45)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isOn ? .primary : .secondary)
                        .lineLimit(1)
                    if isCaptureApp(entry) {
                        Label("may be recording or in a call", systemImage: "record.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 4)
                Text(MenuView.fmt(entry.resident))
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isOn ? Color.teal.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 9) {
            if !model.reclaimSession.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.blue)
                    Text("\(model.reclaimSession.count) paused by the last run")
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

            Toggle(isOn: $rememberOptOuts) {
                Text("Don't offer the unticked apps again")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(freeing > 0 ? "Frees about \(MenuView.fmt(freeing))" : "Nothing selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(freeing > 0 ? .primary : .secondary)
                Spacer()
                Button("Cancel", action: onDone)
                Button("Pause \(chosen.count)") {
                    if rememberOptOuts {
                        for entry in candidates where !selected.contains(entry.id) {
                            model.setExcludedFromReclaim(true, for: entry)
                        }
                    }
                    model.reclaim(selected: chosen)
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }
}
