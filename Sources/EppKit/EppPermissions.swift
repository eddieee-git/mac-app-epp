import AppKit
import ApplicationServices
import ScreenCaptureKit

/// macOS 권한. Mac은 권한을 기능이 아니라 앱(Epp) 하나에 준다. 그래서 Epp 설정 → 일반 → 권한 한 곳에서 다룬다.
public enum EppPermission: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case screenRecording

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return EppText.t("손쉬운 사용", "Accessibility")
        case .screenRecording: return EppText.t("화면 기록", "Screen Recording")
        }
    }

    /// 시스템 설정의 해당 쪽
    var settingsURL: URL? {
        switch self {
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}

/// 기능이 어떤 권한을 왜 쓰는지. Epp 일반 → 권한에 "필요한 기능"으로 보여 준다.
public struct EppPermissionNeed: Sendable {
    public let permission: EppPermission
    /// 없으면 그 기능이 아예 동작하지 않는지
    public let required: Bool
    public let reasonKo: String
    public let reasonEn: String

    public init(_ permission: EppPermission, required: Bool, reasonKo: String, reasonEn: String) {
        self.permission = permission
        self.required = required
        self.reasonKo = reasonKo
        self.reasonEn = reasonEn
    }

    public var reason: String { EppLanguage.isKorean ? reasonKo : reasonEn }
}

/// 지금 권한 상태. 여러 화면이 함께 보고, 앞으로 올 때·가끔 다시 확인한다.
@MainActor
public final class EppPermissions: ObservableObject {
    public static let shared = EppPermissions()

    @Published public private(set) var accessibility = AXIsProcessTrusted()
    /// 화면 기록은 `CGPreflightScreenCaptureAccess()`가 틀릴 때가 있어 실제 ScreenCaptureKit 호출로 확인한다.
    /// 시스템 확인 창이 뜨지 않도록, 사용자가 한 번 요청한 뒤나 macOS가 이미 허용됐다고 할 때만 호출한다.
    @Published public private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    private static let requestedKey = "requestedScreenCapture"
    private var probing = false

    private init() {}

    public func isGranted(_ permission: EppPermission) -> Bool {
        switch permission {
        case .accessibility: return accessibility
        case .screenRecording: return screenRecording
        }
    }

    public func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibility { accessibility = trusted }
        probeScreenRecording()
    }

    /// 시스템 확인 창을 띄우고 시스템 설정의 해당 쪽을 연다.
    public func request(_ permission: EppPermission) {
        switch permission {
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            openSettings(permission)
        case .screenRecording:
            // macOS는 한 번 캡처를 시도한 앱만 화면 기록 목록에 넣는다.
            UserDefaults.standard.set(true, forKey: Self.requestedKey)
            if CGRequestScreenCaptureAccess() { screenRecording = true; return }
            Task {
                _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                try? await Task.sleep(for: .milliseconds(800))
                openSettings(permission)
            }
        }
    }

    public func openSettings(_ permission: EppPermission) {
        if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
    }

    private func probeScreenRecording() {
        guard !probing, UserDefaults.standard.bool(forKey: Self.requestedKey) || CGPreflightScreenCaptureAccess() else { return }
        probing = true
        Task {
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ok = !(content?.windows.isEmpty ?? true)
            probing = false
            if ok != screenRecording { screenRecording = ok }
        }
    }
}
