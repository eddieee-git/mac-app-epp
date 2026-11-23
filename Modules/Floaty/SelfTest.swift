import AppKit
import Carbon
import CryptoKit
import EppKit

/// `Epp --self-test`(scripts/test.sh)가 돌리는 스티커 점검. 실제 스티커·설정은 건드리지 않는다.
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
        expect(Localization.english["새 스티커"] != nil, "영어 사전 읽기")
        expect(Localization.duplicateKeys.isEmpty, "사전에 같은 키 없음 \(Localization.duplicateKeys)")

        print("단축키")
        expect(KeyCombo.defaults.count == HotKeyAction.allCases.count, "동작마다 기본 단축키")
        expect(KeyCombo.defaults[HotKeyAction.newNote.rawValue]?.displayText == "⌃⌘N", "새 스티커 기본 ⌃⌘N")
        let migrated = KeyCombo.migrated(["collapseAll": KeyCombo.renameDefault])
        expect(migrated[HotKeyAction.toggleCollapse.rawValue] == KeyCombo.renameDefault, "옛 단축키 옮기기")

        print("저장")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("floaty-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteStore(directory: dir)
        expect(store.isFirstRun && store.activeNotes.isEmpty, "처음에는 빈 목록")
        var note = Note()
        note.title = "점검"
        store.upsert(note)
        store.saveBody(NSAttributedString(string: "본문"), id: note.id)
        store.flush()
        let reopened = NoteStore(directory: dir)
        expect(reopened.activeNotes.first?.title == "점검", "다시 열면 그대로")
        expect(reopened.loadBody(id: note.id)?.string == "본문", "본문 저장")
        reopened.trash(id: note.id)
        expect(reopened.activeNotes.isEmpty && reopened.trashedNotes.count == 1, "휴지통으로")
        expect(reopened.restore(id: note.id) != nil && reopened.activeNotes.count == 1, "휴지통에서 되살리기")

        print("잠근 스티커")
        let key = SymmetricKey(size: .bits256)
        NoteCrypto.testKey = key
        defer { NoteCrypto.testKey = nil }
        var locked = Note()
        locked.isLocked = true
        reopened.upsert(locked)
        reopened.saveBody(NSAttributedString(string: "비밀 메모"), id: locked.id)
        reopened.flush()
        let raw = (try? Data(contentsOf: reopened.bodyFileURL(locked.id))) ?? Data()
        expect(EppCrypto.isEncrypted(raw) && raw.range(of: Data("비밀 메모".utf8)) == nil, "잠근 스티커 본문은 암호화")
        expect(NoteStore(directory: dir).loadBody(id: locked.id)?.string == "비밀 메모", "잠근 스티커 다시 열기")
        let index = (try? String(contentsOf: dir.appendingPathComponent("notes.json"), encoding: .utf8)) ?? ""
        expect(!index.contains("비밀 메모"), "목록 파일에 잠근 본문이 없음")
        // 예전 Floaty 방식으로 잠근 본문도 읽는다.
        let legacy = Data("FLTYENC1".utf8) + ((try? AES.GCM.seal(Data("옛 메모".utf8), using: key).combined) ?? Data())
        expect((try? NoteCrypto.decrypt(legacy)) == Data("옛 메모".utf8), "예전 방식 잠금 풀기")
        NoteCrypto.testKey = SymmetricKey(size: .bits256)
        expect((try? NoteCrypto.decrypt(raw)) == nil, "다른 키로는 못 풂")
        NoteCrypto.testKey = key

        print("설정")
        let suite = "floaty-selftest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, directory: dir)
        expect(settings.hotKeys == KeyCombo.defaults, "기본 단축키")
        expect(settings.opacity > 0.3 && settings.newNoteWidth >= 200, "기본값")
        settings.newNoteWidth = 400
        expect(AppSettings(defaults: defaults, directory: dir).newNoteWidth == 400, "바꾼 값 저장")
        return failures == 0
    }
}
