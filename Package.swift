// swift-tools-version:5.10
import PackageDescription

// 새 기능을 더할 때:
// 1. Modules/<이름>/ 폴더를 만들고 EppModule 약속을 따르는 클래스를 넣는다.
// 2. 아래 `modules`에 이름을 한 줄 더한다.
// 3. Sources/Epp/ModuleList.swift의 목록에 한 줄 더한다.
let modules = ["Keepy"]

let package = Package(
    name: "Epp",
    platforms: [.macOS(.v14)],
    targets: [
        // 모든 기능이 같이 쓰는 부품: 기능 약속, 전역 단축키, 언어
        .target(name: "EppKit", path: "Sources/EppKit"),
        // 본체: 메뉴바 아이콘, 설정 창, 기능 켜기/끄기
        .executableTarget(
            name: "Epp",
            dependencies: ["EppKit"] + modules.map { .target(name: $0) },
            path: "Sources/Epp"
        ),
    ] + modules.map {
        .target(name: $0, dependencies: ["EppKit"], path: "Modules/\($0)")
    }
)
