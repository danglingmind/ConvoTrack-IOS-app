import Foundation
import CoreLocation
import UIKit
import CryptoKit

/// A representative photo for a ride's destination — the image Google Maps shows for that place.
struct DestinationPhoto: Equatable {
    let image: UIImage
    /// Photographer credit returned alongside the photo. Google's Places policy requires this
    /// to be displayed wherever the photo appears, so it travels with the image rather than
    /// being an optional extra the UI can forget.
    let attribution: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.image === rhs.image && lhs.attribution == rhs.attribution
    }
}

/// What a destination-photo hero should currently show. Three cases rather than an optional
/// image because "still resolving" and "there is no photo" have to look different: collapsing
/// them means the fallback appears for a beat and is then replaced by the photo, which reads as
/// a glitch. Shared by the lobby hero and the home screen's active-ride card.
enum DestinationHeroPhase: Equatable {
    /// Nothing known yet, or a lookup is in flight. Callers show neither photo nor fallback.
    case resolving
    case photo(DestinationPhoto)
    /// No photo for this place, or the lookup failed — callers show their fallback.
    case unavailable
}

/// Fetches the photo Google Maps shows for a destination, for use as the ride lobby's hero
/// image in place of the route map.
///
/// The backend stores a destination as name + coordinate only (no place ID), so this resolves
/// the place itself: a Text Search biased to that coordinate, then the nearest candidate's
/// first photo. Uses the current Places API (`places.googleapis.com`, field-masked so we're
/// billed only for the fields we read) rather than the legacy endpoint `GooglePlacesService`
/// still uses — legacy Places is closed to new customers and on a sunset path.
///
/// Three tiers, cheapest first: an in-memory `NSCache`, then a disk cache under Caches/, then
/// the two billable network calls. A destination that is edited produces a different cache key,
/// so it misses all tiers and refetches without any explicit invalidation.
///
/// EVERY failure path returns nil — empty name, no match, a match too far away, a place with
/// no photos, HTTP error, decode failure, non-image bytes — because the caller's contract is
/// "show the photo if there is one, otherwise fall back to the route map". Nothing here throws.
actor GooglePlacePhotoService {
    static let shared = GooglePlacePhotoService()

    /// Longest edge we ever hold decoded. The lobby hero is 393×420pt, so at 3× the most that
    /// can be seen is ~1260px; beyond ~1200 extra pixels cost memory and show nothing. A 16:9
    /// photo at this size decodes to ~3MB — the 4000×2250 original Google serves would be 36MB.
    /// Applied to the LONGEST edge, so a portrait photo is bounded by its height too, and the
    /// aspect ratio is always preserved.
    static let maxDecodedPixelSize = 1200

    /// How far a candidate may sit from the stored destination and still count as the same
    /// place. Generous on purpose: a large destination (a hill, a park, a beach) has a centroid
    /// well away from whichever point the ride leader tapped. Tight enough to reject a
    /// same-named place in another city, which is the failure this guard exists for.
    private static let maxCandidateDistance: CLLocationDistance = 5_000

    /// `NSCache` rather than a dictionary specifically so decoded images are evicted under
    /// memory pressure instead of being held until the app dies — the lobby hero is by far the
    /// largest image this app keeps. Cost is the decoded byte count, not the file size.
    private let memory: NSCache<NSString, CacheEntry> = {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 4
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    /// Destinations known to have no photo, so a legitimately photo-less place doesn't re-run
    /// two billable requests. Mirrored on disk, so it survives a relaunch too.
    private var knownEmpty: Set<String> = []
    /// De-duplicates concurrent requests for the same destination so two views appearing at
    /// once can't double-bill the search.
    private var inFlight: [String: Task<FetchedPhoto?, Never>] = [:]
    private var didPrune = false

    private final class CacheEntry {
        let photo: DestinationPhoto
        init(_ photo: DestinationPhoto) { self.photo = photo }
    }

    private struct FetchedPhoto {
        /// Original bytes as served, kept undecoded so the disk copy is never re-compressed.
        let data: Data
        let attribution: String?
    }

    func photo(destinationName: String, coordinate: CLLocationCoordinate2D) async -> DestinationPhoto? {
        let query = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let key = Self.cacheKey(query: query, coordinate: coordinate)

        if let hit = memory.object(forKey: key as NSString) { return hit.photo }
        if knownEmpty.contains(key) { return nil }

        // Housekeeping once per launch, before the first disk read.
        if !didPrune {
            didPrune = true
            DiskCache.prune()
        }

        switch DiskCache.load(key: key) {
        case .empty:
            knownEmpty.insert(key)
            return nil
        case .photo(let data, let attribution):
            if let photo = decodeAndRemember(data: data, attribution: attribution, key: key) {
                return photo
            }
            // Unreadable file — drop it and fall through to the network rather than
            // serving nothing for the next 30 days.
            DiskCache.remove(key: key)
        case .miss:
            break
        }

        let fetched: FetchedPhoto?
        if let running = inFlight[key] {
            fetched = await running.value
        } else {
            let task = Task<FetchedPhoto?, Never> {
                await Self.fetch(query: query, near: coordinate)
            }
            inFlight[key] = task
            fetched = await task.value
            inFlight[key] = nil
        }

        guard let fetched else {
            knownEmpty.insert(key)
            DiskCache.storeEmpty(key: key)
            return nil
        }

        DiskCache.store(key: key, imageData: fetched.data, attribution: fetched.attribution)
        guard let photo = decodeAndRemember(data: fetched.data, attribution: fetched.attribution, key: key) else {
            // Bytes arrived but aren't a decodable image. Record it as empty so we don't pay
            // for the same two requests on every appearance.
            DiskCache.remove(key: key)
            DiskCache.storeEmpty(key: key)
            knownEmpty.insert(key)
            return nil
        }
        return photo
    }

    private func decodeAndRemember(data: Data, attribution: String?, key: String) -> DestinationPhoto? {
        guard let image = Self.downsampled(data: data, maxPixelSize: Self.maxDecodedPixelSize) else { return nil }
        let photo = DestinationPhoto(image: image, attribution: attribution)
        memory.setObject(CacheEntry(photo), forKey: key as NSString, cost: Self.decodedByteCost(image))
        return photo
    }

    /// Coordinates are rounded to ~100 m so tiny differences in an otherwise identical
    /// destination still hit the same entry, while a genuinely edited destination (new name or a
    /// move of more than ~100 m) produces a new key and therefore a refetch.
    private static func cacheKey(query: String, coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude  * 1000).rounded() / 1000
        let lng = (coordinate.longitude * 1000).rounded() / 1000
        return "\(query.lowercased())|\(lat),\(lng)|\(maxDecodedPixelSize)"
    }

    // MARK: - Decoding

    /// Decodes straight to the size we display, via ImageIO's thumbnail path. The full-size
    /// bitmap is never materialised: `CGImageSourceCreateThumbnailAtIndex` downsamples during
    /// decode, so a 4000px original costs the memory of a 1200px one. `maxPixelSize` bounds the
    /// longest edge, so proportions are preserved and nothing is cropped — the lobby shows the
    /// whole frame, so a crop here would undo that.
    private static func downsampled(data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,         // decode now, off the main thread
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func decodedByteCost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    // MARK: - Disk cache

    /// Photos and "this place has no photo" markers persisted under Caches/, so a relaunch
    /// costs no API calls. Caches/ is the correct home: the OS may evict it under storage
    /// pressure and it is excluded from backups, and everything here is re-derivable.
    private enum DiskCache {
        /// Place photos are effectively static, so entries live a long time. Empty markers
        /// expire sooner, since a place that has no photo today may gain one.
        static let photoTTL: TimeInterval = 30 * 24 * 3600
        static let emptyTTL: TimeInterval =  7 * 24 * 3600
        /// Bounds the directory. Riders revisit few destinations, so this is generous.
        static let maxEntries = 20

        enum Entry {
            case photo(Data, attribution: String?)
            case empty
            case miss
        }

        private struct Meta: Codable {
            let attribution: String?
            let isEmpty: Bool
        }

        private static var directory: URL? {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            else { return nil }
            let dir = caches.appendingPathComponent("DestinationPhotos", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }

        /// SHA-256 of the key. Swift's `Hasher` is seeded per-launch, so its values are unusable
        /// as filenames — they would miss on every relaunch, silently defeating the cache.
        private static func basename(for key: String) -> String {
            SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        static func load(key: String) -> Entry {
            guard let dir = directory else { return .miss }
            let base = basename(for: key)
            let metaURL = dir.appendingPathComponent("\(base).json")
            guard let metaData = try? Data(contentsOf: metaURL),
                  let meta = try? JSONDecoder().decode(Meta.self, from: metaData)
            else { return .miss }

            let age = -((try? metaURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSinceNow ?? 0)
            guard age < (meta.isEmpty ? emptyTTL : photoTTL) else {
                remove(key: key)
                return .miss
            }

            if meta.isEmpty { return .empty }
            guard let imageData = try? Data(contentsOf: dir.appendingPathComponent("\(base).jpg")) else {
                return .miss
            }
            return .photo(imageData, attribution: meta.attribution)
        }

        static func store(key: String, imageData: Data, attribution: String?) {
            guard let dir = directory else { return }
            let base = basename(for: key)
            try? imageData.write(to: dir.appendingPathComponent("\(base).jpg"), options: .atomic)
            if let meta = try? JSONEncoder().encode(Meta(attribution: attribution, isEmpty: false)) {
                try? meta.write(to: dir.appendingPathComponent("\(base).json"), options: .atomic)
            }
        }

        static func storeEmpty(key: String) {
            guard let dir = directory,
                  let meta = try? JSONEncoder().encode(Meta(attribution: nil, isEmpty: true))
            else { return }
            try? meta.write(to: dir.appendingPathComponent("\(basename(for: key)).json"), options: .atomic)
        }

        static func remove(key: String) {
            guard let dir = directory else { return }
            let base = basename(for: key)
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(base).jpg"))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(base).json"))
        }

        /// Drops expired entries, then the oldest entries beyond `maxEntries`. Run once per
        /// launch — a destination the rider no longer visits would otherwise sit here forever.
        static func prune() {
            guard let dir = directory,
                  let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
            else { return }

            var entries: [(base: String, date: Date, isEmpty: Bool)] = []
            for name in names where name.hasSuffix(".json") {
                let base = String(name.dropLast(5))
                let url = dir.appendingPathComponent(name)
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let isEmpty = (try? Data(contentsOf: url))
                    .flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }?.isEmpty ?? false
                entries.append((base, date, isEmpty))
            }

            var live: [(base: String, date: Date)] = []
            for entry in entries {
                let ttl = entry.isEmpty ? emptyTTL : photoTTL
                if -entry.date.timeIntervalSinceNow >= ttl {
                    removeFiles(base: entry.base, in: dir)
                } else {
                    live.append((entry.base, entry.date))
                }
            }

            guard live.count > maxEntries else { return }
            for entry in live.sorted(by: { $0.date < $1.date }).prefix(live.count - maxEntries) {
                removeFiles(base: entry.base, in: dir)
            }
        }

        private static func removeFiles(base: String, in dir: URL) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(base).jpg"))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(base).json"))
        }
    }

    // MARK: - Network

    private static func fetch(query: String, near coordinate: CLLocationCoordinate2D) async -> FetchedPhoto? {
        guard let candidate = await searchPlace(query: query, near: coordinate),
              let data = await photoData(photoName: candidate.photoName)
        else { return nil }
        return FetchedPhoto(data: data, attribution: candidate.attribution)
    }

    private struct Candidate {
        let photoName: String
        let attribution: String?
    }

    /// Nearest place to `coordinate` matching `query` that actually has a photo.
    private static func searchPlace(query: String, near coordinate: CLLocationCoordinate2D) async -> Candidate? {
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchText") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GoogleMapsConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // Field mask is required by this API and also caps what we're charged for.
        request.setValue(
            "places.location,places.photos.name,places.photos.authorAttributions",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        let body: [String: Any] = [
            "textQuery": query,
            "maxResultCount": 5,
            "locationBias": [
                "circle": [
                    "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                    "radius": 20_000.0
                ]
            ]
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = payload

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data),
              // A query with no results returns `{}`, so `places` is legitimately absent.
              let places = decoded.places
        else { return nil }

        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let ranked = places.compactMap { place -> (distance: CLLocationDistance, candidate: Candidate)? in
            guard let location = place.location,
                  let photo = place.photos?.first else { return nil }
            let distance = target.distance(
                from: CLLocation(latitude: location.latitude, longitude: location.longitude)
            )
            guard distance <= maxCandidateDistance else { return nil }
            let author = photo.authorAttributions?.compactMap(\.displayName).first
            return (distance, Candidate(photoName: photo.name, attribution: author))
        }

        return ranked.min { $0.distance < $1.distance }?.candidate
    }

    /// The media endpoint answers with a 302 to the image bytes; `URLSession` follows that for
    /// us. `maxWidthPx` keeps the download itself small — the downsample on decode then bounds
    /// the longest edge, which is what protects us from a tall portrait original.
    private static func photoData(photoName: String) async -> Data? {
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(photoName)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: String(maxDecodedPixelSize)),
            URLQueryItem(name: "key", value: GoogleMapsConfig.apiKey)
        ]
        guard let url = components?.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return nil }
        return data
    }

    // MARK: - Response models

    private struct SearchResponse: Decodable {
        let places: [Place]?

        struct Place: Decodable {
            let location: LatLng?
            let photos: [Photo]?
        }
        struct LatLng: Decodable {
            let latitude: Double
            let longitude: Double
        }
        struct Photo: Decodable {
            let name: String
            let authorAttributions: [Author]?
        }
        struct Author: Decodable {
            let displayName: String?
        }
    }
}
