import AppKit
import Carbon
import CryptoKit
import EppKit

/// `Epp --self-test`(scripts/test.sh)가 돌리는 Keepy 점검. 실제 기록·설정·클립보드는 건드리지 않는다.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func expect(_ condition: Bool, _ name: String) {
        print(condition ? "  ✓ \(name)" : "  ✗ \(name)")
        if !condition { failures += 1 }
    }

    static func run() -> Bool {
        failures = 0
        print("번역")
        expect(Localization.duplicateKeys.isEmpty, "사전에 같은 키 없음 \(Localization.duplicateKeys)")
        expect(Localization.english["%ld자"] == "%ld characters", "영어 사전 읽기")

        reader()
        store()
        storeAgeAndMigration()
        settings()

        return failures == 0
    }

    private static func reader() {
        print("클립보드 읽기")
        // 실제 클립보드 대신 이름 없는 임시 클립보드를 쓴다.
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("안녕 Keepy", forType: .string)
        let text = PasteboardReader.read(pb)
        expect(text?.kind == .text && text?.text == "안녕 Keepy", "텍스트")

        pb.clearContents()
        pb.setString("   \n ", forType: .string)
        expect(PasteboardReader.read(pb) == nil, "빈칸뿐인 텍스트는 기록 안 함")

        pb.clearContents()
        pb.setString("안녕 Keepy\n", forType: .string)
        expect(PasteboardReader.read(pb)?.hash == text?.hash, "앞뒤 빈칸만 다르면 같은 항목")

        pb.clearContents()
        pb.setString(String(repeating: "a", count: PasteboardReader.maxTextBytes + 1), forType: .string)
        expect(PasteboardReader.read(pb) == nil, "너무 긴 글은 기록 안 함")

        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString("secret", forType: .string)
        expect(PasteboardReader.read(pb) == nil, "비밀번호 관리자 숨김 표시는 기록 안 함")

        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/tmp/keepy-test.txt") as NSURL])
        let file = PasteboardReader.read(pb)
        expect(file?.kind == .file && file?.filePaths == ["/tmp/keepy-test.txt"], "파일")

        pb.clearContents()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        pb.setData(rep.representation(using: .png, properties: [:]), forType: .png)
        let image = PasteboardReader.read(pb)
        expect(image?.kind == .image && image?.detail == "4×3", "이미지와 크기")
    }

    private static func store() {
        print("기록 저장")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("keepy-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var limit = 3
        let crypto = EppCrypto(testKey: SymmetricKey(size: .bits256))
        let store = HistoryStore(directory: dir, limit: { limit }, maxAgeDays: { 0 }, crypto: crypto)

        func content(_ s: String) -> CapturedContent {
            CapturedContent(kind: .text, text: s, hash: PasteboardReader.textHash(s))
        }
        for s in ["a", "b", "c"] { store.add(content(s), sourceBundleID: nil, sourceAppName: nil) }
        expect(store.items.map(\.text) == ["c", "b", "a"], "최근 것이 위로")

        store.add(content("a"), sourceBundleID: nil, sourceAppName: nil)
        expect(store.items.map(\.text) == ["a", "c", "b"], "같은 내용은 하나만, 맨 위로")
        store.add(content("a\n"), sourceBundleID: nil, sourceAppName: nil)
        expect(store.items.map(\.text) == ["a\n", "c", "b"], "빈칸만 다르면 하나로, 새로 복사한 글로")
        store.add(content("a"), sourceBundleID: nil, sourceAppName: nil)

        store.togglePin(store.items[2].id) // b 고정
        store.add(content("d"), sourceBundleID: nil, sourceAppName: nil)
        store.add(content("e"), sourceBundleID: nil, sourceAppName: nil)
        expect(store.items.map(\.text) == ["e", "d", "a", "b"], "한도를 넘으면 오래된 것부터, 고정은 남김")

        let png = Data([0x89, 0x50, 0x4E, 0x47])
        store.add(CapturedContent(kind: .image, pngData: png, detail: "1×1", hash: "img"), sourceBundleID: nil, sourceAppName: nil)
        let imageItem = store.items[0]
        expect(store.blobData(imageItem.imageFile) == png, "이미지 파일 저장")

        store.delete(imageItem.id)
        expect(!store.items.contains { $0.id == imageItem.id }, "삭제")
        store.undoDelete()
        expect(store.items.first?.id == imageItem.id && store.blobData(imageItem.imageFile) == png, "삭제 되돌리기")
        store.delete(imageItem.id)
        store.commitDeletion()
        expect(store.blobData(imageItem.imageFile) == nil, "되돌리기를 끝내면 파일도 지움")

        store.saveNow()
        let reopened = HistoryStore(directory: dir, limit: { limit }, maxAgeDays: { 0 }, crypto: crypto)
        expect(reopened.items.map(\.text) == store.items.map(\.text), "다시 열면 그대로")
        let index = (try? Data(contentsOf: dir.appendingPathComponent("history.json"))) ?? Data()
        expect(EppCrypto.isEncrypted(index) && index.range(of: Data("\"text\"".utf8)) == nil, "기록 파일은 암호화해서 저장")
        let blobs = (try? FileManager.default.contentsOfDirectory(at: store.blobDirectory, includingPropertiesForKeys: nil)) ?? []
        expect(blobs.allSatisfy { EppCrypto.isEncrypted((try? Data(contentsOf: $0)) ?? Data()) }, "이미지·서식 파일도 암호화")
        let otherKey = HistoryStore(directory: dir, limit: { limit }, maxAgeDays: { 0 },
                                    crypto: EppCrypto(testKey: SymmetricKey(size: .bits256)))
        expect(otherKey.items.isEmpty, "다른 키로는 읽지 못함")
        otherKey.saveNow()
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        expect(kept.contains { $0.hasPrefix("history-unreadable-") }, "읽지 못한 기록 파일은 덮어쓰지 않고 옆에 남김")

        limit = 1
        reopened.clear(includingPinned: false)
        expect(reopened.items.map(\.text) == ["b"], "기록 지우기는 고정을 남김")
        reopened.clear(includingPinned: true)
        expect(reopened.items.isEmpty, "모두 지우기")
    }

    private static func storeAgeAndMigration() {
        print("오래된 기록, 예전 평문 기록")
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("keepy-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let crypto = EppCrypto(testKey: SymmetricKey(size: .bits256))

        // 암호화 전 Keepy가 남긴 평문 기록(기록 하나 + 이미지 하나)
        try? fm.createDirectory(at: dir.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        let old = Date().addingTimeInterval(-10 * 86_400)
        let items = [
            ClipItem(id: UUID(), kind: .text, text: "new", rtfFile: nil, imageFile: nil, filePaths: [], detail: nil,
                     sourceBundleID: nil, sourceAppName: nil, createdAt: Date(), lastUsedAt: Date(), pinned: false, contentHash: "n"),
            ClipItem(id: UUID(), kind: .image, text: "", rtfFile: nil, imageFile: "old.png", filePaths: [], detail: nil,
                     sourceBundleID: nil, sourceAppName: nil, createdAt: old, lastUsedAt: old, pinned: true, contentHash: "o"),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(items).write(to: dir.appendingPathComponent("history.json"))
        try? Data([1, 2, 3]).write(to: dir.appendingPathComponent("blobs/old.png"))

        let store = HistoryStore(directory: dir, limit: { 100 }, maxAgeDays: { 7 }, crypto: crypto)
        expect(store.items.count == 2, "예전 평문 기록을 읽음")
        expect(store.blobData("old.png") == Data([1, 2, 3]), "예전 이미지도 읽음")
        let index = (try? Data(contentsOf: dir.appendingPathComponent("history.json"))) ?? Data()
        let blob = (try? Data(contentsOf: dir.appendingPathComponent("blobs/old.png"))) ?? Data()
        expect(EppCrypto.isEncrypted(index) && EppCrypto.isEncrypted(blob), "읽은 뒤 바로 암호화해 둠")

        store.togglePin(items[1].id) // 고정을 풀면 10일 지난 항목은 지워진다
        expect(store.items.map(\.text) == ["new"], "7일 지난 기록은 지움(고정은 남김)")
        store.trim(now: Date().addingTimeInterval(8 * 86_400))
        expect(store.items.isEmpty, "시간이 지나면 지움")
    }

    private static func settings() {
        print("설정")
        let suite = "keepy-selftest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        expect(first.hotKey == .openHistoryDefault, "기본 단축키")
        expect(KeyCombo.openHistoryDefault.displayText == "⌃⌥V", "기본 단축키는 ⌃⌥V")
        expect(first.historyLimit == AppSettings.defaultHistoryLimit && first.pasteAutomatically, "기본값")
        first.hotKey = nil
        expect(AppSettings(defaults: defaults).hotKey == nil, "단축키를 끈 것도 저장")
        first.hotKey = KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), key: "C")
        expect(AppSettings(defaults: defaults).hotKey?.displayText == "⇧⌘C", "바꾼 단축키 저장")

        expect(AppSettings.parseBundleIDs(" com.a \n\n com.b\n") == ["com.a", "com.b"], "제외 앱 목록 읽기")
        expect(AppSettings.parseBundleIDs(AppSettings.defaultIgnoredApps).contains("com.apple.keychainaccess"), "기본 제외 앱")
        first.ignoredApps = ""
        expect(first.ignoredBundleIDs.contains("com.1password.1password"), "목록을 비워도 비밀번호 관리자는 늘 제외")
    }
}
