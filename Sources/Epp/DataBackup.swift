import AppKit
import CommonCrypto
import CryptoKit
import EppKit
import UniformTypeIdentifiers

/// 데이터 모두 내보내기·가져오기: 설정 + 모든 기능의 내용(클립보드 기록, 스티커, 캡처, 타이머 등) + 암호화 열쇠를 파일 하나로.
/// 새 Mac으로 옮길 때 쓴다(iCloud 없이).
///
/// 내용은 Mac마다 다른 키체인 열쇠로 암호화돼 있어서, 열쇠도 함께 넣어야 새 Mac에서 열 수 있다.
/// 그래서 파일 전체를 사용자가 정한 암호로 다시 암호화한다(PBKDF2-SHA256 → AES-GCM). 암호를 잊으면 열 수 없다.
@MainActor
enum DataBackup {
    static let magic = Data("EPPBAK1".utf8)
    static let format = "epp-backup-1"
    /// 내용을 암호화하는 열쇠들(기능별 EppCrypto 계정)
    static let keyAccounts = ["keepy-history", "floaty-locked-notes", "grabby-captures"]

    // MARK: 파일 형식

    static func seal(_ payload: [String: Any], password: String) throws -> Data {
        let plain = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard let combined = try AES.GCM.seal(plain, using: deriveKey(password, salt: salt)).combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return magic + salt + combined
    }

    /// 암호가 틀리거나 Epp 백업이 아니면 nil.
    static func open(_ data: Data, password: String) -> [String: Any]? {
        guard data.starts(with: magic), data.count > magic.count + 16 else { return nil }
        let salt = data.subdata(in: magic.count..<magic.count + 16)
        guard let box = try? AES.GCM.SealedBox(combined: data.dropFirst(magic.count + 16)),
              let plain = try? AES.GCM.open(box, using: deriveKey(password, salt: salt)),
              let payload = try? PropertyListSerialization.propertyList(from: plain, format: nil) as? [String: Any],
              payload["format"] as? String == format else { return nil }
        return payload
    }

    static func deriveKey(_ password: String, salt: Data) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8).map { Int8(bitPattern: $0) }
        salt.withUnsafeBytes { saltBytes in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, passwordBytes.count,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &derived, 32)
        }
        return SymmetricKey(data: derived)
    }

    // MARK: 폴더 ↔ zip

    static var dataFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ModuleManager.folderName, isDirectory: true)
    }

    static func zip(_ folder: URL) throws -> Data {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("epp-backup-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: target) }
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", folder.path, target.path])
        return try Data(contentsOf: target)
    }

    static func unzip(_ data: Data, into folder: URL) throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("epp-restore-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: source) }
        try data.write(to: source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", source.path, folder.path])
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: 화면

    static func exportWithPanel(manager: ModuleManager) {
        guard let password = askPassword(title: L("백업 암호 정하기"),
                                         message: L("이 암호로 백업 파일을 잠가요. 새 Mac에서 가져올 때 필요하고, 잊으면 열 수 없어요."),
                                         confirm: true) else { return }
        let panel = NSSavePanel()
        panel.title = L("데이터 모두 내보내기")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Epp \(formatter.string(from: Date())).eppbackup"
        panel.allowedContentTypes = [UTType(filenameExtension: "eppbackup") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 저장하지 않은 내용이 파일에 남도록 기능을 잠시 멈췄다 다시 켠다.
        manager.stopAll()
        defer { manager.startEnabled() }
        do {
            var keys: [String: Data] = [:]
            for account in keyAccounts { keys[account] = EppCrypto(account: account).exportKey() }
            let main = UserDefaults.standard.persistentDomain(forName: ModuleManager.bundleID) ?? [:]
            var modules: [String: [String: Any]] = [:]
            for type in ModuleList.all {
                modules[type.info.id] = UserDefaults.standard.persistentDomain(forName: ModuleManager.defaultsSuite(for: type.info)) ?? [:]
            }
            let payload: [String: Any] = [
                "format": format,
                "settings": SettingsBackup.snapshot(main: main, modules: modules),
                "keys": keys,
                "data": try zip(dataFolder),
            ]
            try seal(payload, password: password).write(to: url, options: .atomic)
            EppToast.show(L("데이터를 모두 내보냈어요"), symbol: "checkmark.circle.fill")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func importWithPanel(manager: ModuleManager) {
        let panel = NSOpenPanel()
        panel.title = L("데이터 모두 가져오기")
        panel.allowedContentTypes = [UTType(filenameExtension: "eppbackup") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard let password = askPassword(title: L("백업 암호"), message: L("내보낼 때 정한 암호를 넣어 주세요."), confirm: false) else { return }
        guard let payload = open(data, password: password) else {
            let alert = NSAlert()
            alert.messageText = L("백업을 열지 못했어요")
            alert.informativeText = L("암호가 틀렸거나 Epp 백업 파일이 아니에요.")
            alert.runModal()
            return
        }
        let confirm = NSAlert()
        confirm.messageText = L("이 백업으로 바꿀까요?")
        confirm.informativeText = L("지금 Epp의 설정과 내용(클립보드 기록, 스티커, 캡처, 타이머 등)을 백업으로 바꾸고 Epp를 다시 열어요. 지금 내용은 데이터 폴더 옆에 \"이전\" 폴더로 남겨 둬요.")
        confirm.addButton(withTitle: L("바꾸고 다시 열기"))
        confirm.addButton(withTitle: L("취소"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        manager.stopAll()
        do {
            // 지금 내용은 지우지 않고 옆에 남긴다.
            let fm = FileManager.default
            if fm.fileExists(atPath: dataFolder.path) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
                let aside = dataFolder.deletingLastPathComponent()
                    .appendingPathComponent("\(ModuleManager.folderName) 이전 \(formatter.string(from: Date()))", isDirectory: true)
                try fm.moveItem(at: dataFolder, to: aside)
            }
            if let zipped = payload["data"] as? Data { try unzip(zipped, into: dataFolder) }
            for (account, key) in payload["keys"] as? [String: Data] ?? [:] { try EppCrypto(account: account).importKey(key) }
            if let settings = payload["settings"] as? [String: Any],
               let plist = try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0),
               let decoded = SettingsBackup.decode(plist) {
                SettingsBackup.apply(decoded)
            }
            EppApp.relaunch()
        } catch {
            NSAlert(error: error).runModal()
            manager.startEnabled()
        }
    }

    /// 암호를 묻는다. confirm이면 두 번 넣게 한다. 취소하면 nil.
    private static func askPassword(title: String, message: String, confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let first = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        first.placeholderString = L("암호")
        let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        second.placeholderString = L("한 번 더")
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: confirm ? 54 : 24))
        if confirm {
            stack.addSubview(first)
            stack.addSubview(second)
        } else {
            first.frame.origin.y = 0
            stack.addSubview(first)
        }
        alert.accessoryView = stack
        alert.addButton(withTitle: L("확인"))
        alert.addButton(withTitle: L("취소"))
        alert.window.initialFirstResponder = first
        while alert.runModal() == .alertFirstButtonReturn {
            let password = first.stringValue
            if password.count < 6 {
                alert.informativeText = L("암호는 6자 이상으로 정해 주세요.")
                continue
            }
            if confirm, password != second.stringValue {
                alert.informativeText = L("두 암호가 달라요. 다시 넣어 주세요.")
                continue
            }
            return password
        }
        return nil
    }
}
