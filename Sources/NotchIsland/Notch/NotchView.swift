import ServiceManagement
import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel

    /// Slightly underdamped, so the island "plops" open like the iPhone's.
    private let spring = Animation.spring(response: 0.45, dampingFraction: 0.7)

    var body: some View {
        let mode = vm.mode
        let size = vm.size(for: mode)
        let shape = NotchShape(topRadius: vm.topRadius(for: mode), bottomRadius: vm.bottomRadius(for: mode))

        ZStack(alignment: .top) {
            switch mode {
            case .expanded:
                // Laid out at full size and revealed by the growing shape, so nothing reflows mid-animation.
                ExpandedView(vm: vm)
                    .frame(width: vm.expandedSize.width, height: vm.expandedSize.height)
                    .transition(contentTransition)
            case .activity(let activity):
                ActivityView(vm: vm, activity: activity)
                    .frame(width: size.width, height: size.height)
                    .transition(contentTransition)
                    .id(activity)
                    .onTapGesture { vm.isExpanded = true }
            case .collapsed:
                CollapsedView(vm: vm)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                    .onTapGesture { vm.isExpanded = true }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background { IslandBackground(vm: vm, mode: mode) }
        .clipShape(shape)
        .overlay { shape.stroke(.white.opacity(mode == .collapsed ? 0 : 0.08), lineWidth: 1) }
        .shadow(color: .black.opacity(mode == .collapsed ? 0 : 0.5), radius: 18, y: 8)
        .contextMenu { IslandMenu() }
        .animation(spring, value: mode)
        .animation(spring, value: vm.showsEars)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                .combined(with: .offset(y: -6))
                .animation(spring.delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }
}

/// Black, with a soft glow of the artwork or the pop-up's color bleeding in from the left.
private struct IslandBackground: View {
    @ObservedObject var vm: NotchViewModel
    let mode: NotchViewModel.Mode

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black
            switch mode {
            case .expanded:
                if let artwork = vm.media.current?.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 300, height: 300)
                        .blur(radius: 70)
                        .opacity(0.5)
                        .offset(x: -40)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            case .activity(let activity):
                RadialGradient(colors: [activity.accent(media: vm.media).opacity(0.35), .clear],
                               center: .leading, startRadius: 0, endRadius: 220)
            case .collapsed:
                EmptyView()
            }
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

    var body: some View {
        HStack(spacing: 0) {
            if vm.showsEars {
                ArtworkView(image: vm.media.current?.artwork, size: 22, corner: 6)
                    .shadow(color: vm.media.tint.opacity(0.6), radius: 6)
                    .frame(width: vm.earWidth)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            Color.clear.frame(width: vm.notchSize.width)
            if vm.showsEars {
                AudioBars(isPlaying: true, color: vm.media.tint)
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
                MediaPanel(media: vm.media)
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
