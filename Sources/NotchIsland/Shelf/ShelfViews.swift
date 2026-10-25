import SwiftUI
import UniformTypeIdentifiers

/// The Shelf tab: a drop zone when empty, a row of files otherwise.
struct ShelfPanel: View {
    @ObservedObject var shelf: ShelfService
    /// A file is being dragged over the island.
    let isTargeted: Bool

    var body: some View {
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
                        ShelfButton(title: "AirDrop", symbol: "airplayaudio") { shelf.airDrop(shelf.items) }
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
        .onAppear { shelf.refresh() }
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
