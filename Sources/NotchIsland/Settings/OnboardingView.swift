import ServiceManagement
import SwiftUI

/// Four short pages on first launch: what it is, media, calendar, and open at login.
struct OnboardingView: View {
    @ObservedObject var calendar: CalendarService
    let finish: () -> Void

    @State private var step = 0
    @State private var openAtLogin = true
    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page(for: step)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack {
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("Back") { go(to: step - 1) }
                }
                Button(step == lastStep ? "Get Started" : "Continue") {
                    step == lastStep ? complete() : go(to: step + 1)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 540, height: 460)
    }

    private func go(to newStep: Int) {
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { step = newStep }
    }

    private func complete() {
        let item = SMAppService.mainApp
        if openAtLogin, item.status != .enabled { try? item.register() }
        finish()
    }

    @ViewBuilder private func page(for step: Int) -> some View {
        switch step {
        case 0:
            OnboardingPage(
                title: "Meet your notch",
                message: "NotchIsland turns the notch into a live island: what's playing, your next meeting, calls and battery. Hover over the notch to open it."
            ) {
                IslandBadge(width: 220)
            }
        case 1:
            OnboardingPage(
                title: "Works with what you play",
                message: mediaMessage
            ) {
                VStack(spacing: 12) {
                    HStack(spacing: 18) {
                        ForEach(["music.note", "play.rectangle.fill", "waveform"], id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 26))
                                .frame(width: 54, height: 54)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary))
                        }
                    }
                    Button("Show Browser Extension") {
                        if let url = BrowserExtensionRow.extensionURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .disabled(BrowserExtensionRow.extensionURL == nil)
                }
            }
        case 2:
            OnboardingPage(
                title: "Never miss a meeting",
                message: "See your next event with a Join button, and get a heads-up 5 minutes before it starts. You can skip this and turn it on later in Settings."
            ) {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    switch calendar.access {
                    case .granted:
                        Label("Calendar access allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .notDetermined:
                        Button("Allow Calendar Access") { calendar.requestAccess() }
                    case .denied:
                        Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                    }
                }
            }
        default:
            OnboardingPage(
                title: "You're all set",
                message: "Right-click the island anytime for Settings."
            ) {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Toggle("Open NotchIsland at login", isOn: $openAtLogin)
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var mediaMessage: String {
        #if DIRECT_DISTRIBUTION
        "Apple Music and Spotify work right away, and so does every other app that plays audio or video. Add the browser extension for full control of YouTube, Netflix and other tabs."
        #else
        "Apple Music and Spotify work right away. Add the browser extension for YouTube, YouTube Music, Netflix and other tabs in Chrome, Arc, Edge and Brave."
        #endif
    }
}

private struct OnboardingPage<Art: View>: View {
    let title: String
    let message: String
    @ViewBuilder let art: Art

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            art
                .frame(height: 130)
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
