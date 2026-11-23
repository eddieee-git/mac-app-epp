import AppKit

/// 라이트·다크·시스템.
public enum EppTheme: String, CaseIterable, Sendable {
    case light, dark, system

    public var title: String {
        switch self {
        case .light: return EppText.t("라이트", "Light")
        case .dark: return EppText.t("다크", "Dark")
        case .system: return EppText.t("시스템", "System")
        }
    }

    /// nil이면 시스템 설정을 따른다.
    public var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

/// Epp 전체 테마(설정 → 일반 → 테마). 모든 Epp 창에 똑같이 입힌다(`NSApp.appearance`).
@MainActor
public enum EppAppTheme {
    public static let key = "theme"

    public static var current: EppTheme {
        get { UserDefaults.standard.string(forKey: key).flatMap(EppTheme.init) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            apply()
        }
    }

    public static func apply() {
        NSApp.appearance = current.appearance
    }
}
