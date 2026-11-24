import CoreGraphics
import CryptoKit
import Foundation

/// `Epp --self-test`(scripts/test.sh)가 돌리는 Peeky 점검. 실제 설정·권한·메뉴 막대는 건드리지 않는다.
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
        expect(Localization.english["그룹 %ld"] == "Group %ld", "영어 사전 읽기")

        print("기본 항목 이름")
        expect(SystemItemNames.match("com.apple.menuextra.battery") == "배터리", "배터리")
        expect(SystemItemNames.match("com.apple.menuextra.keyboard-brightness") == "키보드 밝기", "키보드 밝기가 디스플레이보다 먼저")
        expect(SystemItemNames.match("com.apple.menuextra.screenmirroring") == "화면 미러링", "화면 미러링이 디스플레이보다 먼저")
        expect(SystemItemNames.match("com.example.unknown") == nil, "모르는 식별자")
        let unnamed = SystemItemNames.label(bundleID: "com.apple.controlcenter", identifier: nil, description: nil,
                                            title: nil, help: nil, appName: "Control Center", index: 2)
        expect(unnamed != "Control Center", "이름 없는 기본 항목에 번호")
        let thirdParty = SystemItemNames.label(bundleID: "com.example.app", identifier: "x", description: "Sync",
                                               title: nil, help: nil, appName: "Example", index: 0)
        expect(thirdParty == "Sync", "다른 앱은 설명 그대로")

        print("기본 항목 모양")
        expect(SystemItemNames.symbol(bundleID: "com.apple.controlcenter", texts: ["com.apple.menuextra.battery"]) == "battery.75percent",
               "배터리는 배터리 모양")
        expect(SystemItemNames.symbol(bundleID: "com.apple.controlcenter", texts: [nil, "Wi‑Fi", "Wi-Fi"]) == "wifi", "Wi-Fi 모양")
        expect(SystemItemNames.symbol(bundleID: "com.example.app", texts: ["battery"]) == nil, "다른 앱은 앱 아이콘 그대로")

        expect(SystemItemNames.label(bundleID: "org.pqrs.Karabiner-Console-User-Server", identifier: nil, description: nil,
                                     title: "menu", help: nil, appName: "Karabiner-Elements", index: 0) == "Karabiner-Elements",
               "뜻 없는 이름(menu)은 앱 이름으로")
        expect(SystemItemNames.label(bundleID: "com.apple.TextInputMenuAgent", identifier: nil, description: "2-Set Korean",
                                     title: nil, help: nil, appName: "TextInputMenuAgent", index: 0) == L("입력 소스"),
               "입력 소스 이름")

        print("항목 이름")
        expect(firstLine("Cloudflare One Client\n\nAttention - Disconnected") == "Cloudflare One Client",
               "상태가 덧붙은 도움말은 첫 줄만")
        expect(firstLine("  \n") == nil, "빈 문자열은 없음")

        print("순서")
        let sorted = Preferences.ordered(["a", "b", "c", "d"], by: ["c", "a"]) { $0 }
        expect(sorted == ["c", "a", "b", "d"], "저장한 순서 먼저, 나머지는 원래 순서")

        print("아이콘 여백 자르기")
        let canvas = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        canvas.fill(CGRect(x: 10, y: 12, width: 6, height: 4)) // 그림 좌표: 아래에서 12 → 위에서 4
        let cut = canvas.makeImage().flatMap(ImageTools.trimmed)
        expect(cut?.width == 8 && cut?.height == 6, "보이는 부분만 남김(가장자리 1픽셀)")
        let probe = cut.flatMap { ImageTools.analyze($0) }
        expect(probe?.hasContent == true, "잘라 낸 자리에 그림이 있음(위아래가 뒤집히지 않음)")

                print("그룹 설정")
        let suite = "peeky-selftest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs: Preferences = Preferences(defaults: defaults)
        let first = prefs.groups.first?.id
        expect(first != nil, "처음에 그룹 하나")
        let second = prefs.addGroup()
        expect(prefs.groups.count == 2 && second.symbol != prefs.groups[0].symbol, "그룹 더하기(다른 모양)")
        prefs.assign("item.a", to: second.id)
        prefs.assign("item.b", to: nil)
        expect(prefs.group(for: "item.a") == second.id, "아이콘을 그룹에 넣기")
        expect(prefs.group(for: "item.b") == nil, "아이콘 끄기")
        prefs.setOrder(["item.b", "item.a"])
        let again: Preferences = Preferences(defaults: defaults)
        expect(again.groups.count == 2 && again.group(for: "item.a") == second.id && again.itemOrder.prefix(2) == ["item.b", "item.a"],
               "다시 열면 그대로")
        prefs.removeGroup(second.id)
        expect(prefs.groups.count == 1 && prefs.group(for: "item.a") == first, "지운 그룹의 아이콘은 첫 그룹으로")
        prefs.removeGroup(prefs.groups[0].id)
        expect(prefs.groups.count == 1, "마지막 그룹은 지우지 않음")
        print("보이기 · 그룹 · 숨기기")
        prefs.setPlacement(.hide, for: "item.c")
        expect(prefs.placement(for: "item.c") == .hide && prefs.group(for: "item.c") == nil && prefs.wantsHidden("item.c"),
               "숨기기: 메뉴바에서 빼지만 그룹 바에는 없음")
        prefs.setPlacement(.group(prefs.groups[0].id), for: "item.c")
        expect(prefs.placement(for: "item.c") == .group(prefs.groups[0].id) && prefs.wantsHidden("item.c"), "그룹: 메뉴바에서 빼고 그룹 바에")
        prefs.setPlacement(.show, for: "item.c")
        expect(prefs.placement(for: "item.c") == .show && !prefs.wantsHidden("item.c"), "보이기: 메뉴바에 그대로")
        prefs.setPlacement(.hide, for: "item.c")
        expect(Preferences(defaults: defaults).placement(for: "item.c") == .hide, "숨기기도 저장")

        prefs.rowCount = 9
        expect(prefs.rowCount(for: nil) == 3, "줄 수는 3까지")

        return failures == 0
    }
}
