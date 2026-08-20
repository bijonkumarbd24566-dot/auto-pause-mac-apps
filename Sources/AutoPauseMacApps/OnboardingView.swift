import SwiftUI

/// First-run walkthrough. Four short pages that explain what the app does, where it lives,
/// and offer to start it at login — so a menu-bar-only app with no Dock icon and no window
/// doesn't just disappear on first launch.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: WelcomePage()
                case 1: TiersPage()
                case 2: ReclaimPage()
                default: FinishPage(launchAtLogin: $launchAtLogin, loginError: $loginError)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))

            controls
        }
        .frame(width: 520, height: 460)
        .background(BackdropView())
    }

    private var controls: some View {
        HStack {
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(page == pageCount - 1 ? 0 : 1)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == page ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: page)
                }
            }

            Spacer()

            Button(page == pageCount - 1 ? "Start Using It" : "Next") {
                if page == pageCount - 1 {
                    onFinish()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    @State private var breathe = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 96 + CGFloat(ring) * 34)
                        .scaleEffect(breathe ? 1.08 : 0.94)
                        .opacity(breathe ? 0 : 0.9)
                        .animation(.easeOut(duration: 2.4)
                            .repeatForever(autoreverses: false)
                            .delay(Double(ring) * 0.8), value: breathe)
                }
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 92, height: 92)
                    .overlay(
                        Image(systemName: "pause.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white))
                    .shadow(color: .accentColor.opacity(0.35), radius: 18, y: 8)
                    .scaleEffect(appeared ? 1 : 0.7)
            }
            .frame(height: 190)

            Text("Auto Pause Mac Apps")
                .font(.system(size: 26, weight: .bold))
            Text("Reclaim memory from apps you're not using —\nwithout losing your place in any of them.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Label("100% free and open source", systemImage: "heart.fill")
                .font(.caption)
                .foregroundStyle(.pink)
                .padding(.top, 2)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
            breathe = true
        }
    }
}

private struct TiersPage: View {
    @State private var shown = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Two ways to free memory")
                .font(.system(size: 21, weight: .bold))
                .padding(.top, 28)

            TierCard(icon: "pause.circle.fill", tint: .blue, title: "Pause",
                     detail: "Freezes the app and every helper process it owns. Zero CPU, memory handed back, and resuming is instant and exact.",
                     badge: "Instant")
                .offset(y: shown ? 0 : 24).opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: shown)

            TierCard(icon: "moon.zzz.fill", tint: .indigo, title: "Deep Sleep",
                     detail: "Quits the app after its state is saved, releasing all of its memory including swap. Waking restores your windows and tabs.",
                     badge: "Frees everything")
                .offset(y: shown ? 0 : 24).opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.18), value: shown)

            Label("Nothing is ever force-quit — unsaved work always wins",
                  systemImage: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut.delay(0.35), value: shown)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .onAppear { shown = true }
    }
}

private struct TierCard: View {
    let icon: String, tint: Color, title: String, detail: String, badge: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 27))
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(tint)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct ReclaimPage: View {
    @State private var progress: CGFloat = 0
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Need room for a local model?")
                .font(.system(size: 21, weight: .bold))
                .padding(.top, 30)

            Text("Set a target and Auto Pause frees it in one click —\nheaviest apps first, never the one you're using.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            // A meter filling up to illustrate memory being handed back.
            VStack(spacing: 8) {
                HStack {
                    Label("Free Up Memory", systemImage: "cpu.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.teal)
                    Spacer()
                    Text("\(Int(progress * 8)) GB")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(LinearGradient(colors: [.teal, .green],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 9)
            }
            .padding(15)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
            .padding(.horizontal, 34)
            .opacity(shown ? 1 : 0)

            Text("Then **Restore** puts back exactly what it froze.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(shown ? 1 : 0)

            Spacer(minLength: 0)
        }
        .onAppear {
            shown = true
            withAnimation(.easeInOut(duration: 1.6).delay(0.3)) { progress = 1 }
        }
    }
}

private struct FinishPage: View {
    @Binding var launchAtLogin: Bool
    @Binding var loginError: String?
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .offset(y: bounce ? -7 : 3)
                    .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: bounce)
                RoundedRectangle(cornerRadius: 7)
                    .fill(.quaternary.opacity(0.5))
                    .frame(width: 168, height: 30)
                    .overlay(
                        HStack(spacing: 7) {
                            Image(systemName: "pause.circle.fill").foregroundStyle(Color.accentColor)
                            Text("your menu bar").font(.system(size: 11)).foregroundStyle(.secondary)
                        })
            }
            .padding(.top, 26)

            Text("It lives in your menu bar")
                .font(.system(size: 20, weight: .bold))
            Text("There's no Dock icon and no window. Click the pause\nicon near the clock any time to open it.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start automatically at login").font(.system(size: 13, weight: .medium))
                    Text("Recommended — it's only useful when it's running")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(13)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 34)
            .onChange(of: launchAtLogin) { _, wants in
                if case .failure(let error) = LaunchAtLogin.set(wants) {
                    loginError = error.localizedDescription
                    launchAtLogin = LaunchAtLogin.isEnabled
                } else {
                    loginError = nil
                }
            }

            if let loginError {
                Text(loginError)
                    .font(.caption2).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }

            Spacer(minLength: 0)
        }
        .onAppear { bounce = true }
    }
}

/// Subtle tinted backdrop so the window doesn't read as a plain grey sheet.
private struct BackdropView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            RadialGradient(colors: [Color.accentColor.opacity(0.13), .clear],
                           center: .top, startRadius: 5, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
