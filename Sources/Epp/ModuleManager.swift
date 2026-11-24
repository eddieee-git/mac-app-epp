import AppKit
import EppKit

/// 기능 켜기/끄기와 실행 중인 기능을 맡는다.
///
/// - 켠 기능 목록은 Epp 설정(UserDefaults.standard의 "enabledModules")에 저장한다. 처음에는 모두 꺼져 있다.
/// - 단독 실행(`--only <id>`)이면 그 기능 하나만 켜고, 켠 목록은 저장하지 않는다.
@MainActor
final class ModuleManager: ObservableObject {
    private static let enabledKey = "enabledModules"

    /// 단독 실행 중인 기능 id. nil이면 보통 Epp.
    let soloID: String?
    @Published private(set) var enabledIDs: [String]
    private(set) var running: [String: any EppModule] = [:]
    /// 설정 창을 열어 해당 기능을 보여 준다(본체가 채운다).
    var openSettings: (String?) -> Void = { _ in }
    /// 기능을 켜거나 끈 뒤(본체가 앱 메뉴를 다시 모은다).
    var onChange: () -> Void = {}
    /// 본체의 메뉴바 아이콘(본체가 채운다).
    var hostStatusItems: () -> [NSStatusItem] = { [] }
    /// 기능이 Epp 아이콘 옆에 붙이는 글(본체가 채운다). (기능 id, 글 또는 nil)
    var setStatusText: (String, String?) -> Void = { _, _ in }

    init(soloID: String?) {
        self.soloID = soloID
        if let soloID {
            enabledIDs = [soloID]
        } else {
            let saved = UserDefaults.standard.stringArray(forKey: Self.enabledKey) ?? []
            enabledIDs = saved.filter { ModuleList.type(id: $0) != nil }
        }
    }

    /// 켜져 있는 기능을 ModuleList 순서대로
    var enabledTypes: [any EppModule.Type] {
        ModuleList.all.filter { enabledIDs.contains($0.info.id) }
    }

    func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }

    func startEnabled() {
        for type in enabledTypes { launch(type) }
    }

    /// showSettings: 처음 켠 기능이면 그 설정(시작하기)을 연다. 일반 쪽 목록에서 여러 개를 켤 때는 false(쪽이 넘어가지 않게).
    func setEnabled(_ id: String, _ on: Bool, showSettings: Bool = true) {
        guard soloID == nil, let type = ModuleList.type(id: id), on != isEnabled(id) else { return }
        if on {
            enabledIDs.append(id)
            launch(type)
            // 처음 켰으면 그 기능의 설정을 열어 시작하기 상자를 보여 준다.
            let key = "\(id).everEnabled"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                if showSettings { openSettings(id) }
            }
        } else {
            enabledIDs.removeAll { $0 == id }
            running.removeValue(forKey: id)?.stop()
            setStatusText(id, nil)
        }
        UserDefaults.standard.set(enabledIDs, forKey: Self.enabledKey)
        onChange()
    }

    /// 모든 기능을 한꺼번에 켜거나 끈다(일반 → 기능의 "모두 켜기"). 쪽은 넘어가지 않는다.
    func setAllEnabled(_ on: Bool) {
        for info in ModuleList.infos { setEnabled(info.id, on, showSettings: false) }
    }

    var allEnabled: Bool { ModuleList.infos.allSatisfy { isEnabled($0.id) } }

    func stopAll() {
        for module in running.values { module.stop() }
        running.removeAll()
    }

    func module(id: String) -> (any EppModule)? { running[id] }

    /// 기능끼리의 부탁을 켜져 있는 다른 기능에 차례로 건넨다. 누군가 처리하면 true.
    func send(_ request: EppRequest, from sender: String) -> Bool {
        for type in enabledTypes where type.info.id != sender {
            if running[type.info.id]?.handle(request: request) == true { return true }
        }
        // 받을 기능이 꺼져 있으면 그 기능 설정(켜기 버튼이 있는 쪽)을 연다.
        switch request {
        case .makeSticky: openSettings("floaty")
        }
        return false
    }

    /// 빠른 검색: 켠 기능마다 맞는 것을 모은다(기능마다 최대 `limit`개, 기능 목록 순서).
    /// 맨 위에 "실행"(명령), 그 아래 기능마다 찾은 내용.
    func search(_ query: EppSearchQuery, limit: Int = 6) -> [(title: String, results: [EppSearchResult])] {
        guard !query.isEmpty else { return [] }
        let modules = enabledTypes.compactMap { type in running[type.info.id].map { (type.info, $0) } }
        let commands = modules.flatMap { $0.1.commands(query) } + hostCommands(query)
        var groups: [(title: String, results: [EppSearchResult])] = commands.isEmpty ? [] : [(L("실행"), Array(commands.prefix(8)))]
        for (info, module) in modules {
            let results = Array(module.search(query).prefix(limit))
            if !results.isEmpty { groups.append((info.name, results)) }
        }
        return groups
    }

    /// Epp 본체 명령(설정 열기)
    private func hostCommands(_ query: EppSearchQuery) -> [EppSearchResult] {
        guard query.matchesCommand(L("Epp 설정"), "settings", "설정") else { return [] }
        return [EppSearchResult(id: "epp.settings", title: L("Epp 설정 열기"), symbol: "gearshape") { [weak self] in
            self?.openSettings(nil)
        }]
    }

    #if DEBUG
    /// 점검용(-debugCycleModules): 기능을 여러 번 켰다 껐다 하고, 끈 뒤에 남은 것이 없는지 본다.
    /// 문제를 한 줄씩 돌려준다(비어 있으면 통과). 켠 목록(설정)은 바꾸지 않는다.
    func debugCycle(ids: [String], times: Int) async -> [String] {
        var problems: [String] = []
        let hotKeysBefore = HotKey.registeredCount
        let windowsBefore = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        for id in ids {
            guard let type = ModuleList.type(id: id), running[id] == nil else {
                problems.append("\(id): 이미 켜져 있거나 없는 기능이라 건너뜀")
                continue
            }
            var released: [() -> Bool] = []
            for _ in 0..<times {
                launch(type)
                try? await Task.sleep(for: .milliseconds(150))
                guard let module = running.removeValue(forKey: id) else { continue }
                module.stop()
                setStatusText(id, nil)
                weak var weakModule = module as AnyObject
                released.append { weakModule == nil }
            }
            // 미뤄 둔 일(저장 예약 등)이 끝나도록 잠깐 기다린 뒤 본다.
            try? await Task.sleep(for: .seconds(2))
            let leaked = released.filter { !$0() }.count
            if leaked > 0 { problems.append("\(id): 끈 뒤에도 메모리에 남은 기능 객체 \(leaked)/\(times)개") }
            if HotKey.registeredCount != hotKeysBefore {
                problems.append("\(id): 끈 뒤에도 남은 전역 단축키 \(HotKey.registeredCount - hotKeysBefore)개")
            }
            let windows = NSApp.windows.filter { $0.isVisible && !windowsBefore.contains(ObjectIdentifier($0)) }
            if !windows.isEmpty {
                problems.append("\(id): 끈 뒤에도 떠 있는 창 \(windows.count)개 (\(windows.map { $0.title.isEmpty ? String(describing: Swift.type(of: $0)) : $0.title }))")
            }
        }
        return problems
    }
    #endif

    private func launch(_ type: any EppModule.Type) {
        let id = type.info.id
        guard running[id] == nil else { return }
        let module = type.init(context: makeContext(for: type.info))
        running[id] = module
        module.start()
    }

    // MARK: 저장 위치

    /// 번들 ID. 디버그 빌드(Epp Dev)는 다른 번들 ID를 써서 실제 Epp와 설정·데이터가 섞이지 않는다.
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.eddieee.Epp.dev" }
    /// ~/Library/Application Support 아래 폴더 이름 ("Epp" 또는 "Epp Dev")
    static var folderName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Epp Dev"
    }

    static func dataDirectory(for info: EppModuleInfo) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(info.storageName, isDirectory: true)
    }

    /// 기능마다 따로 쓰는 UserDefaults 이름 (예: com.eddieee.Epp.keepy)
    static func defaultsSuite(for info: EppModuleInfo) -> String { "\(bundleID).\(info.id)" }

    private func makeContext(for info: EppModuleInfo) -> EppContext {
        let directory = Self.dataDirectory(for: info)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: Self.defaultsSuite(for: info)) ?? .standard
        return EppContext(moduleID: info.id, defaults: defaults, dataDirectory: directory,
                          openSettings: { [weak self] in self?.openSettings(info.id) },
                          openPermissions: { [weak self] in self?.openSettings("general") },
                          hostStatusItems: { [weak self] in self?.hostStatusItems() ?? [] },
                          appName: Self.folderName,
                          setStatusText: { [weak self] text in self?.setStatusText(info.id, text) },
                          send: { [weak self] request in self?.send(request, from: info.id) ?? false })
    }
}
