import AppKit
import ImageIO

@MainActor
enum IconCache {
    private static let thumbnails = NSCache<NSString, NSImage>()
    private static var appIcons: [String: NSImage] = [:]
    private static var fileIcons = NSCache<NSString, NSImage>()

    /// 기록의 이미지 파일은 암호화돼 있어서 경로가 아니라 푼 데이터를 받는다. 캐시에 없을 때만 data()를 부른다.
    static func thumbnail(key name: String, maxPixel: Int = 96, data: () -> Data?) -> NSImage? {
        let key = name as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let data = data(), let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        thumbnails.setObject(image, forKey: key)
        return image
    }

    static func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }

    static func fileIcon(path: String) -> NSImage {
        let key = path as NSString
        if let cached = fileIcons.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileIcons.setObject(icon, forKey: key)
        return icon
    }
}
