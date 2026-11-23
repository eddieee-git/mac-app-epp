import Foundation
import EppKit

/// 타이머가 쓰는 저장 위치. ClockyModule이 시작할 때 Epp가 준 값으로 채운다.
/// 점검(swift test)에서는 기본값(standard, 임시 폴더)을 쓴다.
enum ClockyStorage {
    /// 타이머 기능 전용 UserDefaults
    nonisolated(unsafe) static var defaults: UserDefaults = .standard
    /// 타이머 데이터 폴더(<Epp 데이터 폴더>/Clocky). 캘린더 캐시(Calendars)와 내 소리(Sounds)가 들어간다.
    nonisolated(unsafe) static var folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Clocky", isDirectory: true)
}
