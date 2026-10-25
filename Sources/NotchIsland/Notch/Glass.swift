import AppKit
import SwiftUI

extension View {
    /// Liquid Glass on macOS 26 and later; earlier systems get a dark frosted blur.
    /// `clear` is Apple's see-through variant: less frosting, so what's behind stays visible.
    @ViewBuilder
    func islandGlass<S: Shape>(in shape: S, tint: Color? = nil, clear: Bool = false,
                               interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(makeGlass(tint: tint, clear: clear, interactive: interactive), in: shape)
        } else {
            background(FrostedBackground().clipShape(shape))
        }
    }
}

@available(macOS 26.0, *)
private func makeGlass(tint: Color?, clear: Bool, interactive: Bool) -> Glass {
    var glass = clear ? Glass.clear : Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

/// The pre-Liquid Glass look: a dark blur of whatever is behind the window.
private struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Light catching the lower edge of the glass. It fades out toward the top, where the island
/// is solid black and meets the notch.
struct GlassRim<S: Shape>: View {
    let shape: S

    var body: some View {
        let edge = LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: 0.3),
                .init(color: .white.opacity(0.3), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        ZStack {
            shape.stroke(edge, lineWidth: 1)
            shape.stroke(edge, lineWidth: 4).blur(radius: 4).opacity(0.35)
        }
        .allowsHitTesting(false)
    }
}
