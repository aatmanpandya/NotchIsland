import SwiftUI
import UniformTypeIdentifiers

/// The Shelf tab: the shelf on the left (70%), an AirDrop zone on the right (30%).
struct ShelfPanel: View {
    @ObservedObject var shelf: ShelfService
    /// A file is being dragged over the island.
    let isTargeted: Bool

    private let gap: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let shelfWidth = (geo.size.width - gap) * 0.7
            HStack(spacing: gap) {
                shelfSide.frame(width: shelfWidth)
                AirDropZone(shelf: shelf)
            }
        }
        .onAppear { shelf.refresh() }
    }

    private var shelfSide: some View {
        Group {
            if shelf.items.isEmpty {
                DropZone(isTargeted: isTargeted)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(shelf.items.count == 1 ? "1 item" : "\(shelf.items.count) items")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        ShelfButton(title: "Clear", symbol: "xmark") {
                            withAnimation(.spring(duration: 0.35, bounce: 0.2)) { shelf.clear() }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items) { item in
                                ShelfTile(item: item, thumbnail: shelf.thumbnails[item.id], shelf: shelf)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .padding(-6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: shelf.items)
    }
}

/// Drop files here to AirDrop them straight away; click to AirDrop everything on the shelf.
private struct AirDropZone: View {
    @ObservedObject var shelf: ShelfService
    @State private var isTargeted = false

    var body: some View {
        let canSendShelf = !shelf.items.isEmpty
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.opacity(isTargeted ? 0.3 : 0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.blue.opacity(isTargeted ? 0.9 : 0.35),
                                      style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [6, 5]))
                }
            VStack(spacing: 6) {
                // Like the AirDrop button in Control Center: blue rings on a white circle.
                AirDropGlyph(lineWidth: 2.2)
                    .foregroundStyle(.blue)
                    .frame(width: 26, height: 26)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white))
                    .shadow(color: .blue.opacity(isTargeted ? 0.6 : 0.25), radius: isTargeted ? 12 : 6)
                    .scaleEffect(isTargeted ? 1.12 : 1)
                Text("AirDrop")
                    .font(.system(size: 13, weight: .semibold))
                Text(isTargeted ? "Drop to send" : canSendShelf ? "Drop files, or click to send the shelf" : "Drop files to send")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
        }
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.3), value: isTargeted)
        .contentShape(Rectangle())
        .onTapGesture { if canSendShelf { shelf.airDrop(shelf.items) } }
        // Takes the drop before the island's own "add to shelf" drop handler does.
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            loadFileURLs(from: providers) { urls in shelf.airDrop(urls: urls) }
            return true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AirDrop")
        .accessibilityHint(canSendShelf ? "Drop files to send them, or press to send everything on the shelf" : "Drop files to send them")
        .accessibilityAddTraits(.isButton)
    }
}

private struct DropZone: View {
    let isTargeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(isTargeted ? 0.7 : 0.25),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isTargeted ? 0.1 : 0.03)))
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.5))
                    .symbolEffect(.bounce, value: isTargeted)
                Text(isTargeted ? "Drop to add" : "Drop files here")
                    .font(.system(size: 13, weight: .semibold))
                Text("They stay on the shelf until you clear them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.3), value: isTargeted)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let thumbnail: NSImage?
    @ObservedObject var shelf: ShelfService

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc").font(.system(size: 28)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 78, height: 26, alignment: .top)
        }
        .frame(width: 82)
        .contentShape(Rectangle())
        // Drag it out into any app or folder, like dragging from Finder.
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.showInFinder([item]) }
            Button("AirDrop") { shelf.airDrop([item]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityHint("Drag to move it into an app or folder; double-click to open")
    }
}

private struct ShelfButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// File URLs from a drop, delivered on the main queue.
func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

/// The AirDrop mark: concentric rings, open at the bottom, around a center dot. Apple doesn't
/// offer it as a public SF Symbol, so it's drawn here.
struct AirDropGlyph: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let diameter = size * (0.4 + CGFloat(ring) * 0.3)
                    Circle()
                        // A gap of about 60 degrees, turned to sit at the bottom.
                        .trim(from: 0.085, to: 0.915)
                        .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(90))
                        .frame(width: diameter, height: diameter)
                }
                Circle().frame(width: size * 0.16, height: size * 0.16)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
