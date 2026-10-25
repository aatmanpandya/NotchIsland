import ServiceManagement
import SwiftUI

/// Every animation setting for the island, in one place for tuning.
enum IslandMotion {
    /// The shape morphing between states. Slightly underdamped, so it "plops" like the iPhone's.
    static let morph = Animation.spring(response: 0.45, dampingFraction: 0.7)
    /// How long new content waits before fading in, so it lands after the shape starts growing.
    static let contentDelay: TimeInterval = 0.06
    /// Old content fades quickly so it never overlaps the new.
    static let fadeOut = Animation.easeOut(duration: 0.1)
    /// New content starts this much smaller and grows into place.
    static let contentScale: CGFloat = 0.9

    // Stretch style: the island widens out of the notch first, then pours downward, and content
    // comes into focus from a blur. Collapsing runs the same steps in reverse.
    static let stretchWidth = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let stretchHeight = Animation.spring(response: 0.46, dampingFraction: 0.72)
    /// Gap between the two steps.
    static let stretchStagger: TimeInterval = 0.07
    static let focusBlur: CGFloat = 12
    static let focusIn = Animation.easeOut(duration: 0.3).delay(0.12)

    /// UserDefaults key for the style picked in the island's right-click menu.
    static let styleKey = "motionStyle"

    // Views that carry the same ID morph into each other instead of fading.
    static let artworkID = "artwork"
    static let barsID = "bars"
}

enum MotionStyle: String, CaseIterable, Identifiable {
    case stretch
    case drop

    var id: Self { self }
    var title: String { self == .stretch ? "Stretch" : "Drop" }
}

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @Namespace private var island
    @AppStorage(IslandMotion.styleKey) private var style: MotionStyle = .stretch
    /// The size actually drawn in the Stretch style, animated one axis at a time.
    @State private var stretchedSize: CGSize?

    var body: some View {
        let mode = vm.mode
        let target = vm.size(for: mode)
        let size = style == .stretch ? (stretchedSize ?? target) : target
        let shape = NotchShape(topRadius: vm.topRadius(for: mode), bottomRadius: vm.bottomRadius(for: mode))

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
                    .onTapGesture { vm.isExpanded = true }
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
        .overlay { if mode != .collapsed { GlassRim(shape: shape) } }
        .shadow(color: .black.opacity(mode == .collapsed ? 0 : 0.35), radius: 24, y: 10)
        .contextMenu { IslandMenu() }
        .animation(IslandMotion.morph, value: mode)
        .animation(IslandMotion.morph, value: vm.showsEars)
        .onAppear { stretchedSize = target }
        .onChange(of: target) { old, new in stretch(from: old, to: new) }
        .onChange(of: style) { stretchedSize = target }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var contentTransition: AnyTransition {
        switch style {
        case .drop:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: IslandMotion.contentScale, anchor: .top))
                    .combined(with: .offset(y: -6))
                    .animation(IslandMotion.morph.delay(IslandMotion.contentDelay)),
                removal: .opacity.animation(IslandMotion.fadeOut)
            )
        case .stretch:
            return .asymmetric(
                insertion: .opacity.combined(with: .focusBlur(IslandMotion.focusBlur))
                    .animation(IslandMotion.focusIn),
                removal: .opacity.combined(with: .focusBlur(IslandMotion.focusBlur / 2))
                    .animation(IslandMotion.fadeOut)
            )
        }
    }

    /// Opening widens first and then grows down; closing pulls up first and then narrows.
    private func stretch(from old: CGSize, to new: CGSize) {
        guard style == .stretch else { return }
        if stretchedSize == nil { stretchedSize = old }
        let opening = new.height > (stretchedSize?.height ?? old.height)
        if opening {
            withAnimation(IslandMotion.stretchWidth) { stretchedSize?.width = new.width }
            withAnimation(IslandMotion.stretchHeight.delay(IslandMotion.stretchStagger)) {
                stretchedSize?.height = new.height
            }
        } else {
            withAnimation(IslandMotion.stretchHeight) { stretchedSize?.height = new.height }
            withAnimation(IslandMotion.stretchWidth.delay(IslandMotion.stretchStagger)) {
                stretchedSize?.width = new.width
            }
        }
    }
}

private struct FocusBlur: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private extension AnyTransition {
    static func focusBlur(_ radius: CGFloat) -> AnyTransition {
        .modifier(active: FocusBlur(radius: radius), identity: FocusBlur(radius: 0))
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
            RadialGradient(colors: [activity.accent(media: vm.media).opacity(0.3), .clear],
                           center: .leading, startRadius: 0, endRadius: 220)
        case .collapsed:
            EmptyView()
        }
    }
}

private struct IslandMenu: View {
    @AppStorage(IslandMotion.styleKey) private var style: MotionStyle = .stretch

    var body: some View {
        Picker("Animation", selection: $style) {
            ForEach(MotionStyle.allCases) { Text($0.title).tag($0) }
        }
        Divider()
        let loginItem = SMAppService.mainApp
        Button(loginItem.status == .enabled ? "Don't Open at Login" : "Open at Login") {
            try? loginItem.status == .enabled ? loginItem.unregister() : loginItem.register()
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
            if vm.showsEars {
                ArtworkView(image: vm.media.current?.artwork, size: 22, corner: 6)
                    .matchedGeometryEffect(id: IslandMotion.artworkID, in: namespace)
                    .shadow(color: vm.media.tint.opacity(0.6), radius: 6)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            Color.clear.frame(width: vm.notchSize.width)
            if vm.showsEars {
                AudioBars(isPlaying: true, color: vm.media.tint)
                    .matchedGeometryEffect(id: IslandMotion.barsID, in: namespace)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
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

    var body: some View {
        let inset = vm.topRadius(for: .expanded) + 20
        VStack(spacing: 0) {
            // The header shares the menu bar row with the hardware notch, so it hugs the sides.
            HStack {
                SourceBadge(snapshot: vm.media.current, tint: vm.media.tint)
                Spacer()
                BatteryIndicator(battery: vm.battery)
            }
            .frame(height: vm.notchSize.height)
            .padding(.horizontal, inset)

            HStack(spacing: 20) {
                MediaPanel(media: vm.media, namespace: namespace)
                LinearGradient(colors: [.clear, .white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: 1)
                ClockPanel(tint: vm.media.current == nil ? .white : vm.media.tint)
                    .frame(width: 156, alignment: .leading)
            }
            .padding(.horizontal, inset)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}

private struct SourceBadge: View {
    let snapshot: PlaybackSnapshot?
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(tint))
            Text(snapshot?.appName ?? "NotchIsland")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private var symbol: String {
        guard let snapshot else { return "sparkles" }
        return snapshot.sourceID == "browser" ? "play.rectangle.fill" : "music.note"
    }
}
