import SwiftUI
import UIKit
import ImageIO
import CryptoKit

// MARK: - Categories

/// Each category has its own freshness window and disk budget, so a burst of one kind of
/// image (say, many avatars) can never evict another kind (the share card the rider just made).
nonisolated enum ImageCategory: String, CaseIterable, Sendable {
    /// Route map snapshots. The key encodes every request parameter, so the bytes behind a key
    /// never change: a long TTL is safe and revalidation is pointless.
    case staticMap
    /// Rider profile photos. The same URL can change content (re-upload), so they are short-lived
    /// and revalidated with ETag / Last-Modified when the server offers them.
    case avatar
    /// Rendered ride-summary share cards (PNG). Content-addressed by the data they were rendered from.
    case summaryCard
    /// Anything else remote and decorative.
    case misc

    /// Freshness window. Upper bound for a server `max-age`; the default when there is none.
    var ttl: TimeInterval {
        switch self {
        case .staticMap:   return 30 * 24 * 3600
        case .avatar:      return 24 * 3600
        case .summaryCard: return 90 * 24 * 3600
        case .misc:        return 7 * 24 * 3600
        }
    }

    /// Per-category disk budget in bytes. The sum is deliberately above `ImageCache.totalBudget`
    /// so the global cap is meaningful too.
    var budget: Int {
        switch self {
        case .staticMap:   return 30 * 1024 * 1024
        case .avatar:      return 20 * 1024 * 1024
        case .summaryCard: return 40 * 1024 * 1024
        case .misc:        return 15 * 1024 * 1024
        }
    }

    /// Whether the server's Cache-Control may shorten `ttl`. Static maps and summary cards are
    /// content-addressed, so a CDN's "max-age=86400" must not force a billable refetch.
    var honoursServerMaxAge: Bool { self == .avatar || self == .misc }
}

// MARK: - Fetch plumbing

/// Validators from a previously stored copy, sent as If-None-Match / If-Modified-Since.
nonisolated struct ImageValidators: Sendable {
    let etag: String?
    let lastModified: String?
}

nonisolated enum ImageFetchResult: Sendable {
    case fresh(Data, etag: String?, lastModified: String?, maxAge: TimeInterval?)
    /// 304: the stored copy is still current.
    case notModified(maxAge: TimeInterval?)
    case failed
}

typealias ImageFetch = @Sendable (ImageValidators?) async -> ImageFetchResult

// MARK: - Cache

/// Two tiers: an `NSCache` of decoded, display-sized images, backed by files under
/// `Caches/ImageCache/v<formatVersion>/<category>/`. Caches/ is the right home: the OS may purge
/// it and it is excluded from backups; everything here is re-derivable.
///
/// Invalidation model (see also each call site's key):
///  - KEY CHANGE: callers put everything that changes the pixels into the key (route hash,
///    size, scale, style, summary data hash), so an edited input is simply a miss.
///  - TTL + validators: expired entries are revalidated (304 keeps them) or refetched. If the
///    network fails the stale copy is served rather than nothing.
///  - TAGS: entries may carry a ride id; `purge(tag:)` removes them when the ride goes away, and
///    `store(... supersede: true)` drops that tag's older entries in the category.
///  - SIZE: per-category and global LRU caps, trimmed at first use each launch and after writes.
///  - FORMAT VERSION: bumping `formatVersion` abandons (and deletes) every older directory.
///  - CORRUPTION: undecodable bytes are deleted and refetched once.
///  - MEMORY WARNINGS clear the decoded tier.
///
/// Decoded images are keyed by (key, maxPixel): the disk copy keeps the original bytes and each
/// caller gets a thumbnail sized for its own display, so a 40pt avatar never holds a 1000px bitmap.
actor ImageCache {
    static let shared = ImageCache()

    /// Bump when the on-disk layout or any category's encoding changes; old data is deleted.
    nonisolated static let formatVersion = 1
    nonisolated static let totalBudget = 100 * 1024 * 1024

    private struct Meta: Codable {
        let key: String
        let category: String
        let tag: String?
        let bytes: Int
        var expiresAt: Date
        var etag: String?
        var lastModified: String?
    }

    private struct Entry {
        var meta: Meta
        var lastAccess: Date
    }

    nonisolated private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private var index: [String: Entry]?          // base filename -> entry; built lazily, once
    private var inFlight: [String: Task<Data?, Never>] = [:]

    private init() {
        let cache = memory
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in cache.removeAllObjects() }
    }

    // MARK: Public API

    /// Memory-tier lookup only; synchronous so a view can seed its first frame without a flash.
    nonisolated func cachedImage(key: String, maxPixel: Int) -> UIImage? {
        memory.object(forKey: Self.memoryKey(key, maxPixel) as NSString)
    }

    /// The decoded image for `key`, from memory, then disk, then `fetch`.
    func image(
        key: String, category: ImageCategory, maxPixel: Int, tag: String? = nil,
        fetch: @escaping ImageFetch
    ) async -> UIImage? {
        let memKey = Self.memoryKey(key, maxPixel) as NSString
        if let hit = memory.object(forKey: memKey) { return hit }

        for attempt in 0..<2 {
            guard let data = await loadData(key: key, category: category, tag: tag,
                                            forceNetwork: attempt > 0, fetch: fetch) else { return nil }
            if let image = Self.downsample(data, maxPixel: maxPixel) {
                memory.setObject(image, forKey: memKey, cost: Self.byteCost(image))
                return image
            }
            // Undecodable (truncated write, an error page cached as an image): drop and refetch once.
            removeEntry(base: Self.basename(key))
        }
        return nil
    }

    /// Plain remote URL, with ETag / Last-Modified / Cache-Control handling. `key` defaults to the URL.
    func image(url: URL, category: ImageCategory, maxPixel: Int, key: String? = nil) async -> UIImage? {
        await image(key: key ?? url.absoluteString, category: category, maxPixel: maxPixel,
                    fetch: Self.httpFetch(url))
    }

    /// Fresh stored bytes for `key` (disk only, no network). Used for the rendered share card.
    func storedData(key: String, category: ImageCategory) -> Data? {
        ensureIndex()
        let base = Self.basename(key)
        guard let entry = index?[base], entry.meta.key == key,
              entry.meta.expiresAt > Date(),
              let data = try? Data(contentsOf: Self.dataURL(base, category)) else { return nil }
        touch(base)
        return data
    }

    /// Stores caller-produced bytes. With `supersede`, older entries in this category that carry
    /// the same `tag` are deleted first (a recomputed summary replaces its previous card).
    func store(data: Data, key: String, category: ImageCategory, tag: String? = nil, supersede: Bool = false) {
        ensureIndex()
        if supersede, let tag {
            for (base, entry) in index ?? [:] where entry.meta.tag == tag && entry.meta.category == category.rawValue {
                removeEntry(base: base)
            }
        }
        write(data: data, key: key, category: category, tag: tag, etag: nil, lastModified: nil,
              expiresAt: Date().addingTimeInterval(category.ttl))
        trim()
    }

    /// Every on-device image for the signed-in account: this cache plus the destination-photo cache.
    static func clearEverything() async {
        await shared.clearAll()
        await GooglePlacePhotoService.shared.clearAll()
        await RideThumbnail.forgetAllDestinations()
    }

    func remove(key: String) { ensureIndex(); removeEntry(base: Self.basename(key)) }

    /// Deletes every entry tagged with `tag` (a ride id) — call when the ride is deleted or left.
    func purge(tag: String) {
        ensureIndex()
        for (base, entry) in index ?? [:] where entry.meta.tag == tag { removeEntry(base: base) }
        memory.removeAllObjects()   // memory keys carry no tag; this is rare, so just drop them all
    }

    /// Sign-out / account switch. Everything here is per-account data.
    func clearAll() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        memory.removeAllObjects()
        index = nil
        if let root = Self.rootDirectory { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: Data loading

    private func loadData(
        key: String, category: ImageCategory, tag: String?, forceNetwork: Bool, fetch: @escaping ImageFetch
    ) async -> Data? {
        ensureIndex()
        let base = Self.basename(key)
        var staleData: Data?
        var validators: ImageValidators?

        if !forceNetwork, let entry = index?[base], entry.meta.key == key {
            if let data = try? Data(contentsOf: Self.dataURL(base, category)) {
                if entry.meta.expiresAt > Date() { touch(base); return data }
                staleData = data
                validators = ImageValidators(etag: entry.meta.etag, lastModified: entry.meta.lastModified)
            } else {
                removeEntry(base: base)
            }
        }

        // One network round trip per key no matter how many views ask at once.
        let flightKey = category.rawValue + "|" + key
        if let running = inFlight[flightKey] { return await running.value }
        let sentValidators = validators
        let task = Task<Data?, Never> {
            switch await fetch(sentValidators) {
            case .fresh(let data, let etag, let lastModified, let maxAge):
                write(data: data, key: key, category: category, tag: tag, etag: etag, lastModified: lastModified,
                      expiresAt: Date().addingTimeInterval(Self.ttl(category, maxAge: maxAge)))
                trim()
                return data
            case .notModified(let maxAge):
                if var entry = index?[base] {
                    entry.meta.expiresAt = Date().addingTimeInterval(Self.ttl(category, maxAge: maxAge))
                    index?[base] = entry
                    saveMeta(entry.meta, base: base, category: category)
                }
                return staleData
            case .failed:
                return staleData   // stale-if-error: an old avatar beats an initial
            }
        }
        inFlight[flightKey] = task
        let result = await task.value
        inFlight[flightKey] = nil
        return result
    }

    nonisolated private static func ttl(_ category: ImageCategory, maxAge: TimeInterval?) -> TimeInterval {
        guard category.honoursServerMaxAge, let maxAge else { return category.ttl }
        return min(maxAge, category.ttl)
    }

    // MARK: Network

    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil   // this cache is the cache; don't keep a second copy in URLCache
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// GET with conditional-request headers; parses ETag, Last-Modified and Cache-Control.
    nonisolated static func httpFetch(_ url: URL) -> ImageFetch {
        { validators in
            var request = URLRequest(url: url)
            if let etag = validators?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let lm = validators?.lastModified { request.setValue(lm, forHTTPHeaderField: "If-Modified-Since") }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse else { return .failed }
            let maxAge = parseMaxAge(http.value(forHTTPHeaderField: "Cache-Control"))
            if http.statusCode == 304 { return .notModified(maxAge: maxAge) }
            guard (200...299).contains(http.statusCode), !data.isEmpty else { return .failed }
            return .fresh(data, etag: http.value(forHTTPHeaderField: "ETag"),
                          lastModified: http.value(forHTTPHeaderField: "Last-Modified"), maxAge: maxAge)
        }
    }

    /// `no-cache` / `no-store` -> 0 (always revalidate); otherwise the max-age seconds.
    nonisolated static func parseMaxAge(_ header: String?) -> TimeInterval? {
        guard let header = header?.lowercased() else { return nil }
        let parts = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.contains("no-store") || parts.contains("no-cache") { return 0 }
        for part in parts where part.hasPrefix("max-age=") {
            return TimeInterval(part.dropFirst("max-age=".count))
        }
        return nil
    }

    // MARK: Disk

    nonisolated private static var rootDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ImageCache", isDirectory: true)
    }

    nonisolated private static func dataURL(_ base: String, _ category: ImageCategory) -> URL {
        (rootDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("v\(formatVersion)", isDirectory: true)
            .appendingPathComponent(category.rawValue, isDirectory: true)
            .appendingPathComponent(base + ".bin")
    }

    nonisolated private static func metaURL(_ base: String, _ category: ImageCategory) -> URL {
        dataURL(base, category).deletingPathExtension().appendingPathExtension("json")
    }

    /// SHA-256 of the key. Swift's `Hasher` is seeded per launch, so it can't name files.
    nonisolated static func basename(_ key: String) -> String { digest(key) }

    /// Stable short digest for building keys from large inputs (route polylines, summary data).
    nonisolated static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func memoryKey(_ key: String, _ maxPixel: Int) -> String { "\(key)#\(maxPixel)" }

    /// Builds the in-memory index from the sidecar files once per launch, repairing as it goes:
    /// older format versions are deleted, orphaned or half-written files are removed, and
    /// over-budget / long-expired entries are trimmed.
    private func ensureIndex() {
        guard index == nil else { return }
        var built: [String: Entry] = [:]
        let fm = FileManager.default
        if let root = Self.rootDirectory, let versions = try? fm.contentsOfDirectory(atPath: root.path) {
            for name in versions where name != "v\(Self.formatVersion)" {
                try? fm.removeItem(at: root.appendingPathComponent(name))
            }
        }
        for category in ImageCategory.allCases {
            let dir = Self.dataURL("x", category).deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                let bin = Self.dataURL(base, category), json = Self.metaURL(base, category)
                if ext == "json" {
                    guard let raw = try? Data(contentsOf: json),
                          let meta = try? JSONDecoder().decode(Meta.self, from: raw),
                          fm.fileExists(atPath: bin.path) else {
                        try? fm.removeItem(at: json); try? fm.removeItem(at: bin); continue
                    }
                    let mtime = (try? bin.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    built[base] = Entry(meta: meta, lastAccess: mtime)
                } else if ext == "bin", !fm.fileExists(atPath: json.path) {
                    try? fm.removeItem(at: bin)   // data without metadata: a write that never finished
                }
            }
        }
        index = built
        trim()
    }

    private func write(data: Data, key: String, category: ImageCategory, tag: String?,
                       etag: String?, lastModified: String?, expiresAt: Date) {
        ensureIndex()
        let base = Self.basename(key)
        let dir = Self.dataURL(base, category).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Data first, metadata second: an entry only exists once both are down.
        guard (try? data.write(to: Self.dataURL(base, category), options: .atomic)) != nil else { return }
        let meta = Meta(key: key, category: category.rawValue, tag: tag, bytes: data.count,
                        expiresAt: expiresAt, etag: etag, lastModified: lastModified)
        saveMeta(meta, base: base, category: category)
        index?[base] = Entry(meta: meta, lastAccess: Date())
    }

    private func saveMeta(_ meta: Meta, base: String, category: ImageCategory) {
        guard let raw = try? JSONEncoder().encode(meta) else { return }
        try? raw.write(to: Self.metaURL(base, category), options: .atomic)
    }

    /// LRU is the data file's modification date, so it survives relaunch without extra bookkeeping.
    private func touch(_ base: String) {
        guard var entry = index?[base], let category = ImageCategory(rawValue: entry.meta.category) else { return }
        entry.lastAccess = Date()
        index?[base] = entry
        try? FileManager.default.setAttributes([.modificationDate: entry.lastAccess],
                                               ofItemAtPath: Self.dataURL(base, category).path)
    }

    private func removeEntry(base: String) {
        let known = index?[base].flatMap { ImageCategory(rawValue: $0.meta.category) }
        index?[base] = nil
        for category in known.map({ [$0] }) ?? ImageCategory.allCases {
            try? FileManager.default.removeItem(at: Self.dataURL(base, category))
            try? FileManager.default.removeItem(at: Self.metaURL(base, category))
        }
    }

    /// Drops entries a week past expiry (past even stale-if-error use), then least-recently-used
    /// entries until each category and the whole cache fit their budgets.
    private func trim() {
        guard let all = index else { return }
        let now = Date()
        for (base, entry) in all where entry.meta.expiresAt.addingTimeInterval(7 * 24 * 3600) < now {
            removeEntry(base: base)
        }
        for category in ImageCategory.allCases {
            evict(over: category.budget) { $0.meta.category == category.rawValue }
        }
        evict(over: Self.totalBudget) { _ in true }
    }

    private func evict(over budget: Int, where matches: (Entry) -> Bool) {
        let members = (index ?? [:]).filter { matches($0.value) }
        var total = members.values.reduce(0) { $0 + $1.meta.bytes }
        guard total > budget else { return }
        for (base, entry) in members.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            guard total > budget else { break }
            total -= entry.meta.bytes
            removeEntry(base: base)
        }
    }

    // MARK: Decoding

    /// ImageIO thumbnail path: downsamples while decoding, so the full bitmap is never materialised,
    /// and decodes now (off the main thread) rather than at first draw.
    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1)
        ] as [CFString: Any] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }

    nonisolated private static func byteCost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }
}

// MARK: - SwiftUI

/// Drop-in for `AsyncImage` backed by `ImageCache`. `placeholder` covers loading AND failure /
/// no URL (every call site falls back to the same initial or tile in both cases). Sized by
/// `pointSize` (longest edge in points) so the bitmap held is only as large as it is shown.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let pointSize: CGFloat
    var category: ImageCategory = .avatar
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    /// Rounded up to 64px steps so near-identical sizes share one decoded copy.
    private var maxPixel: Int { Int((pointSize * displayScale / 64).rounded(.up)) * 64 }

    var body: some View {
        Group {
            if let image { content(Image(uiImage: image)) } else { placeholder() }
        }
        .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        guard let url else { image = nil; return }
        if let hit = ImageCache.shared.cachedImage(key: url.absoluteString, maxPixel: maxPixel) { image = hit; return }
        image = nil
        image = await ImageCache.shared.image(url: url, category: category, maxPixel: maxPixel)
    }
}
