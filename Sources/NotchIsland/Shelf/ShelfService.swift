import AppKit
import QuickLookThumbnailing

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    /// A macOS bookmark: it keeps finding the file after a rename or move.
    let bookmark: Data?

    var name: String { url.lastPathComponent }
}

/// Files parked on the shelf. They're stored as links, not copies, so they use no extra disk
/// space, and they stay until the user clears them. A file that's deleted drops off.
final class ShelfService: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]

    private static let key = "shelf.bookmarks"
    /// Security-scoped bookmarks only apply inside the App Store sandbox.
    private static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    private var accessedURLs: [URL] = []

    init() {
        load()
    }

    deinit {
        accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    /// Adds files that aren't already on the shelf. `persist` is false only in preview mode.
    func add(_ urls: [URL], persist: Bool = true) {
        let existing = Set(items.map(\.url.standardizedFileURL))
        for url in urls where url.isFileURL && !existing.contains(url.standardizedFileURL) {
            let item = ShelfItem(url: url, bookmark: Self.bookmark(for: url))
            items.append(item)
            makeThumbnail(for: item)
        }
        if persist { save() }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        save()
    }

    func clear() {
        items.removeAll()
        thumbnails.removeAll()
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func showInFinder(_ items: [ShelfItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    func airDrop(_ items: [ShelfItem]) {
        airDrop(urls: items.map(\.url))
    }

    func airDrop(urls: [URL]) {
        guard !urls.isEmpty else { return }
        // The app has no Dock icon, so bring the AirDrop picker forward.
        NSApp.activate()
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    /// Follows files that moved since they were shelved, and drops ones that were deleted.
    func refresh() {
        var changed = false
        items = items.compactMap { item in
            if FileManager.default.fileExists(atPath: item.url.path) { return item }
            changed = true
            guard let url = item.bookmark.flatMap(Self.resolve) else {
                thumbnails[item.id] = nil
                return nil
            }
            var moved = item
            moved.url = url
            return moved
        }
        if changed { save() }
    }

    // MARK: - Storage

    private func save() {
        UserDefaults.standard.set(items.compactMap { $0.bookmark ?? Self.bookmark(for: $0.url) }, forKey: Self.key)
    }

    private func load() {
        let saved = UserDefaults.standard.array(forKey: Self.key) as? [Data] ?? []
        items = saved.compactMap { data in
            guard let url = Self.resolve(data) else { return nil }
            if Self.isSandboxed, url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
            return ShelfItem(url: url, bookmark: data)
        }
        items.forEach(makeThumbnail)
        if items.count != saved.count { save() }
    }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: isSandboxed ? [.withSecurityScope] : [],
                              includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: isSandboxed ? [.withSecurityScope] : [],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// The file's icon right away, then a real preview (image, PDF page, video frame) if one exists.
    private func makeThumbnail(for item: ShelfItem) {
        thumbnails[item.id] = NSWorkspace.shared.icon(forFile: item.url.path)
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 120, height: 120),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let image = thumbnail?.nsImage else { return }
            DispatchQueue.main.async { self?.thumbnails[item.id] = image }
        }
    }
}
