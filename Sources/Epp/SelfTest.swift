import AppKit
import Carbon
import CryptoKit
import EppKit

/// `scripts/test.sh`가 돌리는 자체 점검. 본체를 점검한 뒤 모든 기능의 점검을 차례로 돌린다.
/// 실제 설정·데이터·클립보드는 건드리지 않는다.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func expect(_ condition: Bool, _ name: String) {
        print(condition ? "  ✓ \(name)" : "  ✗ \(name)")
        if !condition { failures += 1 }
    }

    static func run() -> Bool {
        print("[Epp] 번역")
        expect(Localization.duplicateKeys.isEmpty, "사전에 같은 키 없음 \(Localization.duplicateKeys)")

        print("[Epp] 기능 목록")
        let ids = ModuleList.all.map { $0.info.id }
        expect(Set(ids).count == ids.count, "기능 id가 겹치지 않음 \(ids)")
        expect(ids.allSatisfy { $0 == $0.lowercased() && !$0.contains(" ") }, "기능 id는 소문자, 빈칸 없음")
        for type in ModuleList.all {
            let suite = ModuleManager.defaultsSuite(for: type.info)
            expect(suite.hasSuffix("." + type.info.id), "\(type.info.name) 설정 저장소 이름 \(suite)")
            expect(ModuleManager.dataDirectory(for: type.info).lastPathComponent == type.info.storageName, "\(type.info.name) 데이터 폴더")
        }

        print("[Epp] 업데이트 (공통)")
        let updateFailures = AppUpdater.selfTest(appName: "Epp", publicKey: AppUpdater.appPublicKey, format: AppUpdater.appSignatureFormat)
        updateFailures.forEach { expect(false, $0) }
        expect(updateFailures.isEmpty, "공통 업데이트 점검")

        print("[Epp] 단축키")
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), key: "V")
        expect(combo.displayText == "⌃⌥V", "단축키 표시")
        expect(combo.menuKey == "v" && combo.menuModifiers == [.control, .option], "메뉴에 쓰는 키")

        print("[Epp] epp:// 주소 몰림 막기")
        var gate = RateGate(limit: 5, per: 10)
        let start = Date()
        let passed = (0..<8).filter { _ in gate.allow(now: start) }.count
        expect(passed == 5, "10초에 5번까지만 받음 (\(passed))")
        expect(gate.allow(now: start.addingTimeInterval(10)), "시간이 지나면 다시 받음")

        print("[Epp] 암호화 (공통)")
        let crypto = EppCrypto(testKey: SymmetricKey(size: .bits256))
        let plain = Data("비밀 내용".utf8)
        let sealed = (try? crypto.encrypt(plain)) ?? Data()
        expect(EppCrypto.isEncrypted(sealed) && sealed.range(of: plain) == nil, "암호화하면 원문이 보이지 않음")
        expect((try? crypto.decrypt(sealed)) == plain, "같은 키로 풂")
        expect((try? crypto.decrypt(plain)) == plain, "예전 평문은 그대로 읽음")
        expect((try? EppCrypto(testKey: SymmetricKey(size: .bits256)).decrypt(sealed)) == nil, "다른 키로는 못 풂")

        print("[Epp] 빠른 검색")
        let query = EppSearchQuery("  회의 메모 ")
        expect(query.words == ["회의", "메모"], "낱말 나누기")
        expect(query.matches("오늘 회의", "메모 정리") && !query.matches("오늘 회의"), "낱말이 모두 있어야 맞음(여러 글에 나뉘어도)")
        expect(EppSearchQuery("CAFÉ").matches("cafe 가기"), "대소문자·악센트 무시")
        expect(!EppSearchQuery("   ").matches("아무거나") && EppSearchQuery("").isEmpty, "빈 검색은 아무것도 안 맞음")
        expect(EppSearchQuery("5분").duration == 300 && EppSearchQuery("1시간 30분").duration == 5400
               && EppSearchQuery("10m").duration == 600 && EppSearchQuery("회의 메모").duration == nil, "시간 읽기(5분, 1시간 30분, 10m)")
        expect(EppSearchQuery("캡").matchesCommand("캡처") && EppSearchQuery("새 스티커 장보기").matchesCommand("새 스티커")
               && !EppSearchQuery("타이").matchesCommand("캡처"), "명령 이름 맞추기")
        expect(EppSearchQuery("메모").snippet(String(repeating: "가", count: 50) + " 메모 끝")?.hasPrefix("…") == true, "찾은 곳 앞뒤만 보여 줌")

        print("[Epp] 설정 옮기기")
        let snap = SettingsBackup.snapshot(main: ["enabledModules": ["keepy"], "NSWindow Frame x": "1", "lastUpdateCheck": Date()],
                                           modules: ["keepy": ["historyLimit": 500, "NSStatusItem Visible": true]])
        let decoded = (try? SettingsBackup.encode(snap)).flatMap(SettingsBackup.decode)
        expect(decoded?.main["enabledModules"] as? [String] == ["keepy"], "켠 기능을 옮김")
        expect(decoded?.main["NSWindow Frame x"] == nil && decoded?.main["lastUpdateCheck"] == nil, "창 자리·업데이트 시각은 옮기지 않음")
        expect(decoded?.modules["keepy"]?["historyLimit"] as? Int == 500 && decoded?.modules["keepy"]?["NSStatusItem Visible"] == nil,
               "기능 설정을 옮김")
        expect(SettingsBackup.decode(Data("아님".utf8)) == nil, "Epp 설정 파일이 아니면 읽지 않음")

        print("[Epp] 알람 한곳")
        let board = EppAlertBoard.shared
        let alert = EppAlert(id: "test|a|1", title: "시험", date: Date(), source: "test")
        board.publish([alert], from: "test")
        expect(board.alerts.contains(alert) && board.isExternal(alert.id), "알람을 올림")
        var received: (String, EppAlertBoard.Event)?
        board.onEvent(from: "test") { received = ($0, $1) }
        board.ringerDid(.dismissed, alertID: alert.id)
        expect(received?.0 == alert.id, "울리는 쪽에서 끄면 알린 기능에 전함")
        var dismissed: String?
        board.setRinger { dismissed = $0 }
        expect(board.hasRinger, "울리는 기능 등록")
        board.sourceDismissed(alert.id)
        expect(dismissed == alert.id, "알린 쪽에서 끄면 울리는 쪽에 전함")
        board.setRinger(dismiss: nil)
        board.publish([], from: "test")
        board.onEvent(from: "test", nil)
        expect(!board.hasRinger && !board.alerts.contains(alert), "기능을 끄면 정리")

                print("[Epp] 단축키 잠시 풀기")
        let rare = KeyCombo(keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), key: "F19")
        let before = HotKey.registeredCount
        var probe: HotKey? = HotKey(combo: rare) {}
        expect(probe != nil && HotKey.registeredCount == before + 1, "등록")
        HotKey.pauseAll()
        let whilePaused = HotKey(combo: rare) {}
        expect(whilePaused != nil, "입력받는 동안 새로 등록해도 기다렸다가 되살림")
        HotKey.resumeAll()
        probe = nil
        _ = probe
        expect(HotKey.registeredCount == before + 1, "없앤 단축키는 목록에서 빠짐(남은 건 입력 중에 만든 하나)")
        _ = whilePaused

                print("[Epp] 데이터 모두 내보내기")
        let backup = (try? DataBackup.seal(["format": DataBackup.format, "keys": ["k": Data([1, 2, 3])]], password: "abcdef")) ?? Data()
        expect(backup.starts(with: DataBackup.magic) && backup.range(of: Data([1, 2, 3])) == nil, "백업 파일은 암호로 잠김")
        expect((DataBackup.open(backup, password: "abcdef")?["keys"] as? [String: Data])?["k"] == Data([1, 2, 3]), "같은 암호로 엶")
        expect(DataBackup.open(backup, password: "wrong!") == nil, "틀린 암호로는 못 엶")
        let zipDir = FileManager.default.temporaryDirectory.appendingPathComponent("epp-zip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: zipDir.appendingPathComponent("Keepy"), withIntermediateDirectories: true)
        try? Data("기록".utf8).write(to: zipDir.appendingPathComponent("Keepy/history.json"))
        let restored = zipDir.appendingPathComponent("restored")
        if let zipped = try? DataBackup.zip(zipDir.appendingPathComponent("Keepy").deletingLastPathComponent()) {
            try? DataBackup.unzip(zipped, into: restored)
        }
        expect((try? Data(contentsOf: restored.appendingPathComponent("Keepy/history.json"))) == Data("기록".utf8), "폴더를 묶고 그대로 풂")
        try? FileManager.default.removeItem(at: zipDir)

                var ok = failures == 0
        for type in ModuleList.all {
            print("[\(type.info.name)]")
            ok = type.runSelfTest() && ok
        }
        print(ok ? "모두 통과" : "실패가 있어요")
        return ok
    }
}
