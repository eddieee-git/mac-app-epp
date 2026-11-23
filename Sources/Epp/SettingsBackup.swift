import AppKit
import EppKit
import UniformTypeIdentifiers

/// 설정 내보내기·가져오기: Epp와 모든 기능의 설정(켠 기능, 단축키, 테마 등)을 파일 하나로 옮긴다. iCloud 없이 새 Mac으로 옮길 때 쓴다.
/// 내용(클립보드 기록, 스티커, 캡처, 타이머 목록)과 비밀 키는 넣지 않는다. 내용은 데이터 폴더를 따로 복사한다.
@MainActor
enum SettingsBackup {
    static let format = "epp-settings-1"

    /// 옮기지 않는 키: macOS가 쓰는 것(창 자리·메뉴 막대 자리 등), 이 Mac에서만 뜻이 있는 것(업데이트 확인 시각).
    static func isPortable(_ key: String) -> Bool {
        let skipPrefixes = ["NS", "Apple", "com.apple", "WebKit"]
        let skipKeys: Set<String> = ["lastUpdateCheck", "offeredUpdateVersion", "updatedFromVersion"]
        return !skipPrefixes.contains { key.hasPrefix($0) } && !skipKeys.contains(key)
    }

    /// 설정을 묶는다: ["format", "main": 본체 설정, "modules": [기능 id: 설정]]
    static func snapshot(main: [String: Any], modules: [String: [String: Any]]) -> [String: Any] {
        [
            "format": format,
            "main": main.filter { isPortable($0.key) },
            "modules": modules.mapValues { $0.filter { isPortable($0.key) } },
        ]
    }

    static func encode(_ snapshot: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: snapshot, format: .xml, options: 0)
    }

    /// 파일을 읽어 (본체 설정, 기능별 설정)으로 돌려준다. Epp 설정 파일이 아니면 nil.
    static func decode(_ data: Data) -> (main: [String: Any], modules: [String: [String: Any]])? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["format"] as? String == format,
              let main = plist["main"] as? [String: Any],
              let modules = plist["modules"] as? [String: [String: Any]] else { return nil }
        return (main.filter { isPortable($0.key) },
                modules.filter { ModuleList.type(id: $0.key) != nil }.mapValues { $0.filter { isPortable($0.key) } })
    }

    // MARK: - 화면

    @MainActor
    static func exportWithPanel() {
        let panel = NSSavePanel()
        panel.title = L("설정 내보내기")
        panel.nameFieldStringValue = "Epp 설정.eppsettings"
        panel.allowedContentTypes = [UTType(filenameExtension: "eppsettings") ?? .propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundleID = ModuleManager.bundleID
        let main = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        var modules: [String: [String: Any]] = [:]
        for type in ModuleList.all {
            modules[type.info.id] = UserDefaults.standard.persistentDomain(forName: ModuleManager.defaultsSuite(for: type.info)) ?? [:]
        }
        do {
            try encode(snapshot(main: main, modules: modules)).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @MainActor
    static func importWithPanel() {
        let panel = NSOpenPanel()
        panel.title = L("설정 가져오기")
        panel.allowedContentTypes = [UTType(filenameExtension: "eppsettings") ?? .propertyList, .propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let backup = decode(data) else {
            let alert = NSAlert()
            alert.messageText = L("Epp 설정 파일이 아니에요")
            alert.informativeText = L("설정 → 일반 → 설정 옮기기의 \"설정 내보내기…\"로 만든 파일을 골라 주세요.")
            alert.runModal()
            return
        }
        let confirm = NSAlert()
        confirm.messageText = L("이 설정으로 바꿀까요?")
        confirm.informativeText = L("파일에 든 설정으로 덮어쓰고 Epp를 다시 열어요. 클립보드 기록·스티커·캡처 같은 내용은 그대로예요.")
        confirm.addButton(withTitle: L("바꾸고 다시 열기"))
        confirm.addButton(withTitle: L("취소"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        apply(backup)
        EppApp.relaunch()
    }

    /// 가져온 설정을 덮어쓴다(파일에 없는 키는 그대로 둔다).
    @MainActor
    static func apply(_ backup: (main: [String: Any], modules: [String: [String: Any]])) {
        for (key, value) in backup.main { UserDefaults.standard.set(value, forKey: key) }
        for (id, values) in backup.modules {
            guard let info = ModuleList.type(id: id)?.info,
                  let defaults = UserDefaults(suiteName: ModuleManager.defaultsSuite(for: info)) else { continue }
            for (key, value) in values { defaults.set(value, forKey: key) }
        }
    }
}
