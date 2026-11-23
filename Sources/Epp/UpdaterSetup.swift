import AppKit
import EppKit

/// 공통 업데이트(AppUpdater.swift)에 Epp 정보를 넣는다. AppUpdater.swift는 ../mac-app/shared에서 복사해 오므로 여기만 고친다.
extension AppUpdater {
    /// `~/.config/epp/update-signing.key`의 공개 키 (swift scripts/sign-update.swift public)
    nonisolated static let appPublicKey = "TByPbo/vyWhI5QHPpIcX2LQK+GhDYm9cuwKPeYhdzyQ="
    nonisolated static let appSignatureFormat = SignatureFormat.dmg

    static let shared = AppUpdater(.init(
        appName: "Epp",
        repo: "eddieee-git/mac-app-epp",
        publicKey: appPublicKey,
        signatureFormat: appSignatureFormat,
        isEnglish: { !EppLanguage.isKorean },
        didUpdate: { from in
            EppLog.write("업데이트", "updated from \(from)")
            // 새 버전의 서명이 바뀌면 macOS가 손쉬운 사용 권한을 풀 수 있다. 켠 기능이 그 권한을 쓰면 권한 쪽을 바로 보여 준다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    EppPermissions.shared.refresh()
                    guard let delegate = NSApp.delegate as? AppDelegate else { return }
                    let needsAccessibility = delegate.manager.enabledTypes.contains { type in
                        type.permissionNeeds.contains { $0.permission == .accessibility }
                    }
                    if needsAccessibility && !EppPermissions.shared.accessibility {
                        delegate.showSettings(page: SettingsRouter.general)
                    }
                }
            }
        },
        log: { EppLog.write("업데이트", $0) }
    ))

    /// 디버그 빌드(Epp Dev)는 실제 릴리스를 확인하지 않는다. 번들 ID가 달라 설치도 안 되고 시험을 흐린다.
    /// `-debugUpdateURL <시험 서버 주소>`를 줬을 때만 확인한다(scripts/e2e-update.sh).
    static var shouldRun: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "debugUpdateURL") != nil
        #else
        return true
        #endif
    }
}
