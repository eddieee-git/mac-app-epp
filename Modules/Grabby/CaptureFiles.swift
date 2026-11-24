import CoreGraphics
import EppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 캡처 파일(이미지·표시·목록)을 암호화해서 쓰고 읽는다(`EppCrypto`, 키체인 "grabby-captures").
/// 화면에 떠 있던 계좌·대화 같은 내용이 보관함 폴더에 그대로 남지 않게 한다.
/// 예전 평문 파일도 그대로 읽고, 켤 때 한 번 암호화해 둔다(`encryptInPlace`).
/// Finder로 끌어다 놓거나 Finder에서 볼 때만 임시 폴더에 풀어 둔 사본(`plainCopy`)을 쓰고, 다음에 켤 때 지운다.
enum CaptureFiles {
    nonisolated(unsafe) static var crypto = EppCrypto(account: "grabby-captures")

    // MARK: 이미지

    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let data = pngData(image), let sealed = try? crypto.encrypt(data) else { return false }
        return (try? sealed.write(to: url, options: .atomic)) != nil
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 파일에서 이미지를 연다(바로 풀어 둔다). 어느 스레드에서나 불러도 된다.
    static func readImage(_ url: URL) -> CGImage? {
        guard let data = readData(url), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    static func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let data = readData(url), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }

    // MARK: 글(목록·표시)

    static func writeData(_ data: Data, to url: URL) {
        guard let sealed = try? crypto.encrypt(data) else { return }
        try? sealed.write(to: url, options: .atomic)
    }

    /// 암호화한 파일이면 풀고, 예전 평문 파일이면 그대로 돌려준다.
    static func readData(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? crypto.decrypt(data)
    }

    /// 예전 평문 파일을 한 번 암호화해 둔다. 이미 암호화했으면 아무것도 안 한다.
    static func encryptInPlace(_ url: URL) {
        guard let data = try? Data(contentsOf: url), !EppCrypto.isEncrypted(data),
              let sealed = try? crypto.encrypt(data) else { return }
        try? sealed.write(to: url, options: .atomic)
    }

    // MARK: 밖으로 내보낼 사본

    static var exportFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Epp Captures", isDirectory: true)
    }

    /// 다른 앱으로 끌어다 놓거나 Finder에서 볼 평문 PNG 사본. 같은 캡처면 이미 만든 사본을 쓴다.
    static func plainCopy(of url: URL, name: String) -> URL? {
        try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let target = exportFolder.appendingPathComponent(name).appendingPathExtension("png")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        guard let data = readData(url) else { return nil }
        return (try? data.write(to: target, options: .atomic)) != nil ? target : nil
    }

    /// 지난번에 내보낸 사본을 지운다(켤 때·끌 때).
    static func cleanExports() {
        try? FileManager.default.removeItem(at: exportFolder)
    }
}
