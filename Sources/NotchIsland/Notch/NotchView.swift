import ServiceManagement
import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        let expanded = vm.isExpanded
        let size = vm.size(expanded: expanded)

        ZStack(alignment: .top) {
            if expanded {
                // Laid out at full size and revealed by the growing shape, so nothing reflows mid-animation.
                ExpandedView(vm: vm)
                    .frame(width: vm.expandedSize.width, height: vm.expandedSize.height)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                            .animation(spring.delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            } else {
                CollapsedView(vm: vm)
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
                    .onTapGesture { vm.isExpanded = true }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: vm.topRadius(expanded: expanded),
                              bottomRadius: vm.bottomRadius(expanded: expanded)))
        .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 16, y: 6)
        .contextMenu { IslandMenu() }
        .animation(spring, value: expanded)
        .animation(spring, value: vm.showsEars)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
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
            if vm.showsEars { leading.frame(width: vm.earWidth) }
            Color.clear.frame(width: vm.notchSize.width)
            if vm.showsEars { trailing.frame(width: vm.earWidth) }
        }
        .padding(.horizontal, vm.topRadius(expanded: false))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leading: some View {
        switch vm.alert {
        case .charging:
            Image(systemName: "bolt.fill").foregroundStyle(.green)
        case .unplugged:
            Image(systemName: "bolt.slash.fill").foregroundStyle(.white.opacity(0.7))
        case nil:
            ArtworkView(image: vm.media.current?.artwork, size: 20, corner: 5)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch vm.alert {
        case .charging(let level):
            Text("\(level)%").foregroundStyle(.green)
        case .unplugged(let level):
            Text("\(level)%").foregroundStyle(.white.opacity(0.8))
        case nil:
            AudioBars(isPlaying: vm.media.current?.isPlaying == true, color: vm.media.tint)
        }
    }
}

// MARK: - Expanded

private struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        let inset = vm.topRadius(expanded: true) + 18
        VStack(spacing: 0) {
            // The header shares the menu bar row with the hardware notch, so it hugs the sides.
            HStack {
                if let now = vm.media.current {
                    Label(now.appName, systemImage: "waveform")
                } else {
                    Text("NotchIsland")
                }
                Spacer()
                BatteryIndicator(battery: vm.battery)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(height: vm.notchSize.height)
            .padding(.horizontal, inset)

            HStack(spacing: 18) {
                MediaPanel(media: vm.media)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                ClockPanel().frame(width: 150, alignment: .leading)
            }
            .padding(.horizontal, inset)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
    }
}
