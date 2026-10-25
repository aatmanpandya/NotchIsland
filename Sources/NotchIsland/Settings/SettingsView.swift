import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MediaSettings()
                .tabItem { Label("Media", systemImage: "play.circle") }
            PopUpSettings(calendar: calendar)
                .tabItem { Label("Pop-ups", systemImage: "bell.badge") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 440)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(IslandMotion.styleKey) private var style: MotionStyle = .ios
    @AppStorage(Preferences.Key.earsLinger) private var earsLinger = 5
    @AppStorage(Preferences.Key.haptics) private var haptics = true
    @AppStorage(Preferences.Key.liveVisualizer) private var liveVisualizer = false

    var body: some View {
        Form {
            Section {
                LoginItemToggle()
            }
            Section("Island") {
                Picker("Animation", selection: $style) {
                    ForEach(MotionStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Album art beside the notch", selection: $earsLinger) {
                    Text("Never").tag(0)
                    Text("For 3 seconds").tag(3)
                    Text("For 5 seconds").tag(5)
                    Text("For 10 seconds").tag(10)
                    Text("The whole time it plays").tag(-1)
                }
                Toggle("Haptic feedback when it opens", isOn: $haptics)
            }
            Section {
                Toggle("Live visualizer", isOn: $liveVisualizer)
            } footer: {
                Text("The bars move with the actual audio. macOS asks once for permission to listen to system audio. Sound is analyzed on your Mac and never recorded or saved.")
            }
        }
        .formStyle(.grouped)
    }
}

struct LoginItemToggle: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open NotchIsland at login", isOn: $isOn)
            .onChange(of: isOn) { _, wantsOn in
                let item = SMAppService.mainApp
                try? wantsOn ? item.register() : item.unregister()
                // Show what actually happened, in case macOS refused.
                isOn = item.status == .enabled
            }
    }
}

// MARK: - Media

private struct MediaSettings: View {
    @AppStorage(Preferences.Key.source("browser")) private var browser = true
    @AppStorage(Preferences.Key.source(ScriptableAppSource.Target.spotify.bundleID)) private var spotify = true
    @AppStorage(Preferences.Key.source(ScriptableAppSource.Target.music.bundleID)) private var music = true
    @AppStorage(Preferences.Key.source("system")) private var system = true
    @AppStorage(Preferences.Key.popUp("nowPlaying")) private var trackPopUp = true

    var body: some View {
        Form {
            Section {
                Toggle("Browsers (with the extension)", isOn: $browser)
                Toggle("Spotify", isOn: $spotify)
                Toggle("Apple Music", isOn: $music)
                #if DIRECT_DISTRIBUTION
                Toggle("Every other app", isOn: $system)
                #endif
            } header: {
                Text("Show what's playing in")
            } footer: {
                Text("macOS asks once for permission the first time NotchIsland reads Music or Spotify.")
            }
            Section("Browser extension") {
                BrowserExtensionRow()
            }
            Section {
                Toggle("Pop up when a new track starts", isOn: $trackPopUp)
            }
        }
        .formStyle(.grouped)
    }
}

struct BrowserExtensionRow: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Chrome, Arc, Edge and Brave")
                Text("Open chrome://extensions, turn on Developer mode, click Load unpacked and choose this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Show Folder") { revealExtension() }
                .disabled(Self.extensionURL == nil)
        }
    }

    /// Bundled into the app by the build script.
    static var extensionURL: URL? {
        Bundle.main.url(forResource: "ChromeExtension", withExtension: nil)
    }

    private func revealExtension() {
        guard let url = Self.extensionURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Pop-ups

private struct PopUpSettings: View {
    @ObservedObject var calendar: CalendarService
    @AppStorage(Preferences.Key.popUp("charging")) private var charging = true
    @AppStorage(Preferences.Key.popUp("unplugged")) private var unplugged = true
    @AppStorage(Preferences.Key.popUp("fullyCharged")) private var full = true
    @AppStorage(Preferences.Key.popUp("lowBattery")) private var low = true
    @AppStorage(Preferences.Key.popUp("call")) private var call = true
    @AppStorage(Preferences.Key.popUp("meetingSoon")) private var meeting = true
    @AppStorage(Preferences.Key.meetingLeadMinutes) private var lead = 5
    @AppStorage(Preferences.Key.popUp("deviceConnected")) private var device = true
    @AppStorage(Preferences.Key.popUp("timerDone")) private var timerDone = true

    var body: some View {
        Form {
            Section("Battery") {
                Toggle("Charging", isOn: $charging)
                Toggle("Unplugged", isOn: $unplugged)
                Toggle("Fully charged", isOn: $full)
                Toggle("Low battery (20% and 10%)", isOn: $low)
            }
            Section("Calls and meetings") {
                Toggle("A video call starts in the browser", isOn: $call)
                Toggle("Meeting reminder", isOn: $meeting)
                Picker("Remind me", selection: $lead) {
                    Text("1 minute before").tag(1)
                    Text("5 minutes before").tag(5)
                    Text("10 minutes before").tag(10)
                    Text("15 minutes before").tag(15)
                }
                .disabled(!meeting)
                CalendarAccessRow(calendar: calendar)
            }
            VolumeBrightnessSettings()
            Section("Devices and timer") {
                Toggle("A Bluetooth device connects", isOn: $device)
                Toggle("A timer finishes", isOn: $timerDone)
            }
        }
        .formStyle(.grouped)
    }
}

private struct VolumeBrightnessSettings: View {
    @AppStorage(Preferences.Key.popUp("volume")) private var volume = Preferences.isDirectEdition
    @AppStorage(Preferences.Key.popUp("brightness")) private var brightness = Preferences.isDirectEdition
    @AppStorage(Preferences.Key.replaceSystemHUD) private var replaceSystem = false

    var body: some View {
        Section {
            Toggle("Volume", isOn: $volume)
            #if DIRECT_DISTRIBUTION
            Toggle("Brightness", isOn: $brightness)
            Toggle("Hide the system pop-up", isOn: $replaceSystem)
                .disabled(!volume && !brightness)
            if replaceSystem { AccessibilityRow() }
            #endif
        } header: {
            Text("Volume and brightness")
        } footer: {
            #if DIRECT_DISTRIBUTION
            Text("Hiding the system pop-up lets NotchIsland handle the volume and brightness keys itself. macOS asks for Accessibility permission to allow it.")
            #else
            Text("macOS still shows its own volume pop-up as well.")
            #endif
        }
    }
}

#if DIRECT_DISTRIBUTION
/// Whether macOS allows the key takeover, checked every second while Settings is open.
private struct AccessibilityRow: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack {
                Text("Accessibility permission")
                Spacer()
                if MediaKeyTap.isTrusted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
}
#endif

struct CalendarAccessRow: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        HStack {
            Text("Calendar access")
            Spacer()
            switch calendar.access {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("Allow…") { calendar.requestAccess() }
            case .denied:
                Button("Open Privacy Settings") { calendar.openPrivacySettings() }
            }
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            IslandBadge()
                .padding(.bottom, 6)
            Text("NotchIsland")
                .font(.title2.weight(.semibold))
            Text("Version \(Self.version) · \(Self.edition)")
                .foregroundStyle(.secondary)
            Button("Show Welcome Again") { AppWindows.shared.showOnboarding() }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private static var edition: String {
        #if DIRECT_DISTRIBUTION
        "Direct download"
        #else
        "App Store"
        #endif
    }
}

/// A small drawing of the island, used in About and onboarding.
struct IslandBadge: View {
    var width: CGFloat = 150

    var body: some View {
        let height = width * 0.3
        ZStack {
            NotchShape(topRadius: height * 0.18, bottomRadius: height * 0.45)
                .fill(.black)
            HStack {
                RoundedRectangle(cornerRadius: height * 0.15, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: height * 0.5, height: height * 0.5)
                Spacer()
                AudioBars(isPlaying: true, color: .orange, height: height * 0.4)
            }
            .padding(.horizontal, height * 0.45)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}
