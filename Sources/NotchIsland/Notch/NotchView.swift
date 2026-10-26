import SwiftUI

/// Every animation setting for the island, in one place for tuning.
enum IslandMotion {
    // iOS style (default), modeled on the iPhone's Dynamic Island: a springy shape that overshoots
    // and settles, with content that grows out of the island while coming into focus.
    static let springy = Animation.spring(duration: 0.5, bounce: 0.3)
    static let contentIn = springy.delay(0.04)
    static let contentOut = Animation.spring(duration: 0.25, bounce: 0)
    /// Content starts this small and this blurred inside the island.
    static let emergeScale: CGFloat = 0.55
    static let emergeBlur: CGFloat = 18

    // Classic style: the original, gentler drop-in.
    static let morph = Animation.spring(response: 0.45, dampingFraction: 0.7)
    /// How long new content waits before fading in, so it lands after the shape starts growing.
    static let contentDelay: TimeInterval = 0.06
    /// Old content fades quickly so it never overlaps the new.
    static let fadeOut = Animation.easeOut(duration: 0.1)
    /// New content starts this much smaller and grows into place.
    static let contentScale: CGFloat = 0.9

    /// UserDefaults key for the style picked in the island's right-click menu.
    static let styleKey = "motionStyle"

    // Views that carry the same ID morph into each other instead of fading.
    static let artworkID = "artwork"
    static let barsID = "bars"
}

enum MotionStyle: String, CaseIterable, Identifiable {
    case ios
    case classic

    var id: Self { self }
    var title: String { self == .ios ? "iOS" : "Classic" }
    var shape: Animation { self == .ios ? IslandMotion.springy : IslandMotion.morph }
}

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @Namespace private var island
    @AppStorage(IslandMotion.styleKey) private var style: MotionStyle = .ios

    var body: some View {
        let mode = vm.mode
        let size = vm.size(for: mode)
        let shape = NotchShape(topRadius: vm.topRadius(for: mode), bottomRadius: vm.bottomRadius(for: mode))
        // Collapsed, and the slim volume and brightness pop-ups, are plain black like the notch.
        let looksLikeNotch: Bool = {
            if case .activity(let activity) = mode { return activity.isSlim }
            return mode == .collapsed
        }()

        ZStack(alignment: .top) {
            switch mode {
            case .expanded:
                // Laid out at full size and revealed by the growing shape, so nothing reflows mid-animation.
                ExpandedView(vm: vm, namespace: island)
                    .frame(width: vm.expandedSize.width, height: vm.expandedSize.height)
                    .transition(contentTransition)
            case .activity(let activity):
                ActivityView(vm: vm, activity: activity, namespace: island)
                    .frame(width: size.width, height: size.height)
                    .transition(contentTransition)
                    .id(activity)
                    .onTapGesture { if !vm.activityIsInteractive { vm.isExpanded = true } }
            case .collapsed:
                CollapsedView(vm: vm, namespace: island)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(IslandMotion.fadeOut))
                    .onTapGesture { vm.isExpanded = true }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background { IslandBackground(vm: vm, mode: mode) }
        .clipShape(shape)
        // Always present (just hidden when collapsed) so it resizes with the shape instead of
        // appearing at the final size.
        .overlay { GlassRim(shape: shape).opacity(looksLikeNotch ? 0 : 1) }
        .shadow(color: .black.opacity(looksLikeNotch ? 0 : 0.35), radius: 24, y: 10)
        .contextMenu { IslandMenu() }
        .animation(style.shape, value: mode)
        .overlay(alignment: .topTrailing) {
            if mode == .collapsed, vm.showsTimerBubble {
                TimerBubble(timer: vm.timer, stopwatch: vm.stopwatch, size: vm.notchSize.height)
                    .accessibilityLabel(vm.timer.isActive ? "Timer" : "Stopwatch")
                    .accessibilityAddTraits(.isButton)
                    .offset(x: vm.notchSize.height + 6)
                    .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                    .onTapGesture {
                        vm.isExpanded = true
                        vm.tab = .tools
                    }
            }
        }
        .animation(style.shape, value: vm.ears)
        .animation(style.shape, value: vm.showsTimerBubble)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var contentTransition: AnyTransition {
        switch style {
        case .ios:
            return .asymmetric(
                insertion: .emerge(scale: IslandMotion.emergeScale, blur: IslandMotion.emergeBlur)
                    .animation(IslandMotion.contentIn),
                removal: .emerge(scale: 0.75, blur: IslandMotion.emergeBlur * 0.6)
                    .animation(IslandMotion.contentOut)
            )
        case .classic:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: IslandMotion.contentScale, anchor: .top))
                    .combined(with: .offset(y: -6))
                    .animation(IslandMotion.morph.delay(IslandMotion.contentDelay)),
                removal: .opacity.animation(IslandMotion.fadeOut)
            )
        }
    }
}

/// Small, blurred and transparent inside the island at one end; full size and sharp at the other.
private struct Emerge: ViewModifier {
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static func emerge(scale: CGFloat, blur: CGFloat) -> AnyTransition {
        .modifier(active: Emerge(scale: scale, blur: blur, opacity: 0),
                  identity: Emerge(scale: 1, blur: 0, opacity: 1))
    }
}

/// "Black core, glass body": solid black where the island meets the hardware notch, fading into
/// dark glass below, with the artwork or pop-up color glowing through it.
private struct IslandBackground: View {
    @ObservedObject var vm: NotchViewModel
    let mode: NotchViewModel.Mode

    /// How far below the notch the black takes to fade out.
    private let fadeDepth: CGFloat = 24

    var body: some View {
        if mode == .collapsed {
            Color.black
        } else {
            GeometryReader { geo in
                let height = max(geo.size.height, 1)
                let solidEnd = min(1, vm.notchSize.height / height)
                let fadeEnd = min(1, (vm.notchSize.height + fadeDepth) / height)
                ZStack(alignment: .leading) {
                    Color.clear.islandGlass(in: Rectangle(), tint: .black.opacity(0.18), clear: true)
                    glow
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: solidEnd),
                            .init(color: .black.opacity(0), location: fadeEnd),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
        }
    }

    @ViewBuilder private var glow: some View {
        switch mode {
        case .expanded:
            if let artwork = vm.media.current?.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 300, height: 300)
                    .blur(radius: 70)
                    .opacity(0.4)
                    .offset(x: -40)
            }
        case .activity(let activity):
            RadialGradient(colors: [activity.accent(in: vm).opacity(0.3), .clear],
                           center: .leading, startRadius: 0, endRadius: 220)
        case .collapsed:
            EmptyView()
        }
    }
}

private struct IslandMenu: View {
    @AppStorage(IslandMotion.styleKey) private var style: MotionStyle = .ios

    var body: some View {
        Button("Settings…") { AppWindows.shared.showSettings() }
        Picker("Animation", selection: $style) {
            ForEach(MotionStyle.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        Button("Quit NotchIsland") { NSApp.terminate(nil) }
    }
}

// MARK: - Collapsed

private struct CollapsedView: View {
    @ObservedObject var vm: NotchViewModel
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            switch vm.ears {
            case .media:
                ArtworkView(image: vm.media.current?.artwork, size: 22, corner: 6)
                    .matchedGeometryEffect(id: IslandMotion.artworkID, in: namespace)
                    .shadow(color: vm.media.tint.opacity(0.6), radius: 6)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .timer:
                TimerTicker(timer: vm.timer, showsTime: false)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .stopwatch:
                StopwatchTicker(stopwatch: vm.stopwatch, showsTime: false)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .none:
                EmptyView()
            }
            Color.clear.frame(width: vm.notchSize.width)
            switch vm.ears {
            case .media:
                AudioBars(isPlaying: true, color: vm.media.tint)
                    .matchedGeometryEffect(id: IslandMotion.barsID, in: namespace)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .timer:
                TimerTicker(timer: vm.timer, showsTime: true)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .stopwatch:
                StopwatchTicker(stopwatch: vm.stopwatch, showsTime: true)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, vm.topRadius(for: .collapsed))
        .contentShape(Rectangle())
    }
}

// MARK: - Expanded

private struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    let namespace: Namespace.ID
    @State private var isDropTargeted = false

    var body: some View {
        let inset = vm.topRadius(for: .expanded) + 20
        VStack(spacing: 0) {
            // The header shares the menu bar row with the hardware notch, so it hugs the sides.
            HStack {
                TabPills(selection: $vm.tab)
                Spacer()
                BatteryIndicator(battery: vm.battery)
            }
            .frame(height: vm.notchSize.height)
            .padding(.horizontal, inset - 6)

            Group {
                switch vm.tab {
                case .home:
                    HStack(spacing: 20) {
                        MediaPanel(media: vm.media, namespace: namespace)
                        LinearGradient(colors: [.clear, .white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(width: 1)
                        UpNextPanel(calendar: vm.calendar) { vm.holdOpen($0) }
                            .frame(width: 168, alignment: .leading)
                    }
                case .shelf:
                    ShelfPanel(shelf: vm.shelf, isTargeted: isDropTargeted)
                case .tools:
                    ToolsPanel(timer: vm.timer, stopwatch: vm.stopwatch) { vm.holdOpen($0) }
                }
            }
            .id(vm.tab)
            .transition(.opacity.combined(with: .scale(scale: 0.97)).animation(.spring(duration: 0.3, bounce: 0.1)))
            .padding(.horizontal, inset)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        // Files can be dropped anywhere on the open island; it switches to the shelf.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadFileURLs(from: providers) { urls in
                vm.tab = .shelf
                vm.shelf.add(urls)
            }
            return true
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted { withAnimation(.spring(duration: 0.3, bounce: 0.2)) { vm.tab = .shelf } }
        }
    }
}

/// Small tabs in the top row, beside the notch. The selected one shows its name.
private struct TabPills: View {
    @Binding var selection: NotchViewModel.Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchViewModel.Tab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { selection = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                        if selected { Text(tab.title) }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                    .padding(.horizontal, selected ? 10 : 7)
                    .frame(height: 22)
                    .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

extension NotchViewModel.Tab {
    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .tools: "Tools"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.fill"
        case .tools: "timer"
        }
    }
}
