import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads and downsamples images inside the timeline provider so widgets
/// render them synchronously (AsyncImage is unreliable in widgets) and stay
/// within the extension's tight memory budget.
enum ImageLoader {
    /// Fetch `url`, downsample to `maxPixel` on the long edge, re-encode as
    /// JPEG. Returns nil on any failure (caller renders a text fallback).
    static func fetchDownsampled(_ urlString: String?, maxPixel: Int) async -> Data? {
        guard let s = urlString, let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let (data, resp) = try? await rwSession.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return downsample(data: data, maxPixel: maxPixel)
    }

    static func downsample(data: Data, maxPixel: Int) -> Data? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
