import Foundation
import EppKit

/// 캡처가 쓰는 저장 위치. GrabbyModule이 시작할 때 Epp가 준 값으로 채운다.
enum GrabbyStorage {
    /// 캡처 기능 전용 UserDefaults
    nonisolated(unsafe) static var defaults: UserDefaults = .standard
    /// 캡처 데이터 폴더(<Epp 데이터 폴더>/Grabby). 탭 보관함(Captures)과 띄운 캡처(Pins)가 들어간다.
    nonisolated(unsafe) static var folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Grabby", isDirectory: true)
}
