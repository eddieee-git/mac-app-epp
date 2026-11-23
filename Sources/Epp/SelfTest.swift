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

        var ok = failures == 0
        for type in ModuleList.all {
            print("[\(type.info.name)]")
            ok = type.runSelfTest() && ok
        }
        print(ok ? "모두 통과" : "실패가 있어요")
        return ok
    }
}
