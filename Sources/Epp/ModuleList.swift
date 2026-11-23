import EppKit
import Keepy
import Peeky

/// Epp에 들어 있는 기능. 새 기능을 만들면 Package.swift의 `modules`와 여기에 한 줄씩 더한다.
/// 메뉴와 설정 창에 이 순서로 나온다.
@MainActor
enum ModuleList {
    static let all: [any EppModule.Type] = [
        KeepyModule.self,
        PeekyModule.self,
    ]

    /// 화면에 목록을 그릴 때 쓰는 정보 (SwiftUI ForEach는 타입 목록보다 값 목록이 안전하다)
    static var infos: [EppModuleInfo] { all.map { $0.info } }

    static func type(id: String) -> (any EppModule.Type)? {
        all.first { $0.info.id == id }
    }
}
