import AppKit
import EppKit

MainActor.assumeIsolated {
    let args = CommandLine.arguments

    // 자동 점검만 돌리고 끝낸다(scripts/test.sh).
    if args.contains("--self-test") {
        _ = NSApplication.shared
        exit(SelfTest.run() ? 0 : 1)
    }

    // 단독 실행: `--only keepy`면 그 기능 하나만 켜고 메뉴도 그 기능 것만 보여 준다(개발·시험용).
    var soloID: String?
    if let index = args.firstIndex(of: "--only"), args.indices.contains(index + 1) {
        let id = args[index + 1].lowercased()
        guard ModuleList.type(id: id) != nil else {
            let known = ModuleList.all.map { $0.info.id }.joined(separator: ", ")
            FileHandle.standardError.write("모르는 기능: \(id) (있는 기능: \(known))\n".data(using: .utf8)!)
            exit(2)
        }
        soloID = id
    }

    // 하나만 실행: 예전 Epp가 아직 켜져 있으면 끝내고 새로 켠 쪽이 이어받는다.
    // 두 개가 같은 데이터 파일을 서로 덮어쓰면 기록이 빠질 수 있어서다.
    if let id = Bundle.main.bundleIdentifier {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current }
        if !others.isEmpty {
            others.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(3)
            while others.contains(where: { !$0.isTerminated }), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
    }

    let app = NSApplication.shared
    let delegate = AppDelegate(manager: ModuleManager(soloID: soloID))
    app.delegate = delegate
    // 기본은 메뉴바 전용 앱(Dock 아이콘 없음). 설정 → 일반 → "Dock에 아이콘 보이기"를 켜면 일반 앱처럼 보인다.
    // 점검할 때는 `-showInDock YES` 인자로 실행해도 같다(자동화 도구가 찾을 수 있게).
    app.setActivationPolicy(DockIcon.isOn ? .regular : .accessory)
    app.run()
}
