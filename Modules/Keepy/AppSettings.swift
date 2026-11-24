import Carbon
import EppKit
import Foundation

extension KeyCombo {
    /// 기록 열기 기본값 ⌃⌥V. 공통 규칙의 기본 보조 키(⌃⌥)이고, ⇧⌘V(서식 없이 붙여 넣기)처럼 다른 앱이 흔히 쓰는 키와 겹치지 않는다.
    static let openHistoryDefault = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), key: "V")
}

enum PanelPosition: String, CaseIterable, Identifiable {
    case mouse, center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return L("마우스 포인터 위치")
        case .center: return L("화면 가운데")
        }
    }
}

/// UserDefaults에 저장하는 설정. 바꾸면 바로 저장한다.
@MainActor
final class AppSettings: ObservableObject {

    static let historyLimits = [50, 100, 200, 500, 1000]
    static let defaultHistoryLimit = 200
    /// 고정하지 않은 기록을 며칠 지나면 지울지. 0은 지우지 않음.
    static let historyMaxAges = [1, 7, 30, 90, 0]
    static let defaultHistoryMaxAgeDays = 30

    /// 비밀번호 관리자 등 기록하지 않을 앱 (번들 ID, 줄바꿈 구분)
    static let defaultIgnoredApps = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ].joined(separator: "\n")

    private let defaults: UserDefaults

    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    @Published var historyMaxAgeDays: Int { didSet { defaults.set(historyMaxAgeDays, forKey: "historyMaxAgeDays") } }
    @Published var pasteAutomatically: Bool { didSet { defaults.set(pasteAutomatically, forKey: "pasteAutomatically") } }
    @Published var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: "panelPosition") } }
    @Published var ignoredApps: String { didSet { defaults.set(ignoredApps, forKey: "ignoredApps") } }
    @Published var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "isPaused") } }
    /// 기록 열기 전역 단축키. nil이면 끔.
    @Published var hotKey: KeyCombo? { didSet { saveHotKey() } }

    /// 기록 창에서 골라 붙여 넣어 본 적이 있는지(시작하기 3단계)
    @Published var hasPasted: Bool { didSet { defaults.set(hasPasted, forKey: "hasPasted") } }

    /// 단축키를 시스템에 등록하지 못했는지 (저장하지 않음)
    @Published var hotKeyFailed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let limit = defaults.integer(forKey: "historyLimit")
        historyLimit = limit > 0 ? limit : Self.defaultHistoryLimit
        historyMaxAgeDays = defaults.object(forKey: "historyMaxAgeDays") as? Int ?? Self.defaultHistoryMaxAgeDays
        pasteAutomatically = defaults.object(forKey: "pasteAutomatically") as? Bool ?? true
        panelPosition = defaults.string(forKey: "panelPosition").flatMap(PanelPosition.init) ?? .mouse
        ignoredApps = defaults.string(forKey: "ignoredApps") ?? Self.defaultIgnoredApps
        isPaused = defaults.bool(forKey: "isPaused")
        hasPasted = defaults.bool(forKey: "hasPasted")
        if let data = defaults.data(forKey: "hotKey") {
            // 빈 값은 사용자가 단축키를 끈 것
            hotKey = data.isEmpty ? nil : (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? .openHistoryDefault
        } else {
            hotKey = .openHistoryDefault
        }
    }

    /// 목록에서 지워도 늘 기록하지 않는 앱: 비밀번호 관리자. (숨김 표시 없이 복사하는 앱도 있어서)
    static let alwaysIgnored: Set<String> = [
        "com.apple.keychainaccess", "com.apple.Passwords",
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal", "com.lastpass.LastPass",
        "org.keepassxc.keepassxc", "com.markmcguill.strongbox.mac", "in.sinew.Enpass-Desktop",
        "me.proton.pass.electron", "com.nordpass.macos.NordPass",
    ]

    var ignoredBundleIDs: Set<String> { Self.parseBundleIDs(ignoredApps).union(Self.alwaysIgnored) }

    static func parseBundleIDs(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    private func saveHotKey() {
        if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: "hotKey")
        } else {
            defaults.set(Data(), forKey: "hotKey")
        }
    }
}
