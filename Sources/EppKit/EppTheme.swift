import AppKit

/// 기능 창의 테마(스티커·캡처 설정의 "테마"). Epp 전체(`NSApp.appearance`)가 아니라 그 기능의 창에만 입힌다.
/// 앱 전체를 바꾸면 설정 창 등 다른 기능 화면까지 바뀌기 때문이다.
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

/// 한 기능의 창들에 테마를 입힌다. 새 창은 만들 때 `appearance`를 넣고, 테마를 바꾸면 `apply`가 열린 창을 모두 바꾼다.
@MainActor
public final class EppWindowTheme {
    public private(set) var appearance: NSAppearance?
    private let owns: (NSWindow) -> Bool

    /// owns: 이 기능의 창인지
    public init(owns: @escaping (NSWindow) -> Bool) {
        self.owns = owns
    }

    public func apply(_ theme: EppTheme) {
        appearance = theme.appearance
        for window in NSApp.windows where owns(window) { window.appearance = appearance }
    }
}
