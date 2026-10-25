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

    // Views that carry the same ID morph into each other instead of fading.
    static let artworkID = "artwork"
    static let barsID = "bars"
}

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @Namespace private var island

    var body: some View {
        let mode = vm.mode
        let size = vm.size(for: mode)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: IslandMotion.contentScale, anchor: .top))
                .combined(with: .offset(y: -6))
                .animation(IslandMotion.morph.delay(IslandMotion.contentDelay)),
            removal: .opacity.animation(IslandMotion.fadeOut)
        )
    }
}

/// "Black core, glass body": solid black where the island meets the hardware notch, fading into
/// dark glass below, with the artwork or pop-up color glowing through it.
private struct IslandBackground: View {
    @ObservedObject var vm: NotchViewModel
    let mode: NotchViewModel.Mode

    /// How far below the notch the black takes to fade out.
    private let fadeDepth: CGFloat = 44

    var body: some View {
        if mode == .collapsed {
            Color.black
        } else {
            GeometryReader { geo in
                let height = max(geo.size.height, 1)
                let solidEnd = min(1, vm.notchSize.height / height)
                let fadeEnd = min(1, (vm.notchSize.height + fadeDepth) / height)
                ZStack(alignment: .leading) {
                    Color.clear.islandGlass(in: Rectangle(), tint: .black.opacity(0.62))
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
    var body: some View {
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
