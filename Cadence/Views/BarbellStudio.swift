import CadenceCore
import os
import SwiftUI
import UIKit

enum StudioShot: String, Hashable, Sendable {
    case row, hero, blowup
}

final class StudioRenderer: @unchecked Sendable {
    static let shared = StudioRenderer()

    struct Request: Hashable {
        let loadout: Loadout
        let style: PlateVisualStyle
        let theme: PlateThemeID
        let shot: StudioShot
        let width: Int
        let height: Int
        let scale: Double
    }

    /// Bump when the renderer's look changes, so stale disk renders retire.
    /// The directory also carries the build number, so an app update never
    /// shows a render from an older renderer, theme table or texture.
    static let version = 10

    private let queue = DispatchQueue(label: "com.madhakish.cadence.studio", qos: .userInitiated)
    private let cache = NSCache<NSString, UIImage>()
    private static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("StudioRenders", isDirectory: true)
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    private let directory: URL? = StudioRenderer.root?
        .appendingPathComponent("v\(StudioRenderer.version)-\(StudioRenderer.build)", isDirectory: true)

    /// A key that is stable across launches (Swift hash values are not).
    static func key(_ r: Request) -> String {
        let plates = r.loadout.perSide.map { "\($0.plate.exactKey)x\($0.count)" }.joined(separator: ",")
        return "\(r.loadout.bar.id)|\(plates)|\(Weight.trim(r.loadout.collarLb, decimals: 3))|\(r.style.rawValue)|"
            + "\(r.theme.rawValue)|\(r.shot.rawValue)|\(r.width)x\(r.height)@\(Weight.trim(r.scale, decimals: 2))"
    }

    private func file(_ key: String) -> URL? {
        // FNV-1a: a short, deterministic file name for the key.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return directory?.appendingPathComponent(String(hash, radix: 16) + ".png")
    }

    func cached(_ request: Request) -> UIImage? { cache.object(forKey: Self.key(request) as NSString) }

    func render(_ request: Request) async -> UIImage? {
        if let hit = cached(request) { return hit }
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    // A superseded view's request still waits in this serial
                    // queue; skip its snapshot so the current one is not delayed.
                    if cancelled.withLock({ $0 }) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: renderNow(request))
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    func prewarm() {
        queue.async(qos: .utility) { [self] in
            if let root = Self.root, let current = directory?.lastPathComponent,
               let stored = try? FileManager.default.contentsOfDirectory(atPath: root.path) {
                for name in stored where name != current {
                    try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
                }
            }
            _ = UIImage(named: "AstraPhotoStage")
        }
    }

    /// Forgets every stored render, in memory and on disk, so the render lab
    /// measures this build's renderer rather than an earlier run's files.
    func purge() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                cache.removeAllObjects()
                if let directory { try? FileManager.default.removeItem(at: directory) }
                continuation.resume()
            }
        }
    }

    /// Synchronous on the studio queue; also used by the render lab. Memory
    /// first, then the on-disk cache, then a fresh render written back.
    func renderNow(_ request: Request) -> UIImage? {
        let key = Self.key(request)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        guard request.width > 0, request.height > 0 else { return nil }
        let url = file(key)
        if let url, let data = try? Data(contentsOf: url), let disk = UIImage(data: data, scale: CGFloat(request.scale)) {
            cache.setObject(disk, forKey: key as NSString)
            return disk
        }
        guard let image = PhotographicBar.snapshot(request) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        if let url, let data = image.pngData() {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return image
    }


}

/// The compact presentation uses the same per-side order, finishes and
/// denominations as the calculator. It can also draw an unloaded sleeve.
struct StudioLoadoutFallback: View {
    let loadout: Loadout
    let theme: PlateThemeID
    let style: PlateVisualStyle
    var exploded = false

    var body: some View {
        VStack(spacing: 8) {
            if exploded && !loadout.perSide.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(loadout.perSide.enumerated()), id: \.offset) { _, group in
                            VStack {
                                PlateFaceBadge(plateTheme: theme, plate: group.plate, style: style)
                                Text("\(group.plate.label) × \(group.count)")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
            } else {
                PlateStackMini(loadout: loadout, theme: theme, style: style)
                Text(loadout.perSide.isEmpty
                     ? (loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
                     : "Plates per side")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sceneStudio)
    }
}

/// A cached studio render sized to its container.
struct StudioImage: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    let loadout: Loadout
    let style: PlateVisualStyle
    let theme: PlateThemeID
    let shot: StudioShot
    /// The last render and the request it answers; never shown for another request.
    @State private var rendered: (request: StudioRenderer.Request, image: UIImage)?
    @State private var failedRequest: StudioRenderer.Request?

    private struct Render: Equatable {
        let request: StudioRenderer.Request
        let active: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            let request = StudioRenderer.Request(loadout: loadout, style: style, theme: theme, shot: shot,
                                                 width: Int(proxy.size.width.rounded()), height: Int(proxy.size.height.rounded()),
                                                 scale: Double(displayScale))
            ZStack {
                Theme.sceneStudio
                if let shown = StudioRenderer.shared.cached(request) ?? (rendered?.request == request ? rendered?.image : nil) {
                    Image(uiImage: shown)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else if failedRequest == request {
                    StudioLoadoutFallback(loadout: loadout, theme: theme, style: style, exploded: shot == .blowup)
                }
            }
            .task(id: Render(request: request, active: scenePhase == .active)) {
                // Retry the current request when the app returns to the foreground.
                guard scenePhase == .active else { return }
                let image = await StudioRenderer.shared.render(request)
                // A superseded request finishes late; it must not replace the current one.
                guard !Task.isCancelled else { return }
                rendered = image.map { (request: request, image: $0) }
                failedRequest = image == nil ? request : nil
            }
        }
    }
}

extension Plate {
    /// A cache-key component that keeps the stored value's every bit, unlike
    /// `id`, which rounds to two decimals (1.125 and 1.13 share an id).
    var exactKey: String { "\(String(value.bitPattern, radix: 16))-\(unit.rawValue)" }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
