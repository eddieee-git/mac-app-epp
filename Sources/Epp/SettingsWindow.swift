import EppKit
import ServiceManagement
import SwiftUI

/// 설정 창에서 지금 보여 줄 쪽. "general" 또는 기능 id.
@MainActor
final class SettingsRouter: ObservableObject {
    static let general = "general"
    @Published var page: String = SettingsRouter.general
}

@MainActor
final class SettingsWindowController {
    private let manager: ModuleManager
    private let router = SettingsRouter()
    private var window: NSWindow?

    init(manager: ModuleManager) {
        self.manager = manager
        if let solo = manager.soloID { router.page = solo }
    }

    /// page: 기능 id. nil이면 마지막에 보던 쪽 그대로.
    func show(page: String?) {
        if let page { router.page = page }
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(manager: manager, router: router))
            let w = EscClosableWindow(contentViewController: controller)
            w.styleMask = [.titled, .closable]
            w.title = L("Epp 설정")
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: SettingsView.size.width, height: SettingsView.size.height))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 왼쪽: 일반 + 기능 목록, 오른쪽: 고른 쪽의 설정.
private struct SettingsView: View {
    static let size = CGSize(width: 700, height: 640)

    @ObservedObject var manager: ModuleManager
    @ObservedObject var router: SettingsRouter

    var body: some View {
        NavigationSplitView {
            List(selection: $router.page) {
                Label(L("일반"), systemImage: "gearshape").tag(SettingsRouter.general)
                Section(L("기능")) {
                    ForEach(visibleInfos) { info in
                        HStack {
                            Label(info.name, systemImage: info.symbol)
                            Spacer()
                            if !manager.isEnabled(info.id) {
                                Text(L("꺼짐")).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tag(info.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(170)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var visibleInfos: [EppModuleInfo] {
        if let solo = manager.soloID { return ModuleList.infos.filter { $0.id == solo } }
        return ModuleList.infos
    }

    @ViewBuilder private var detail: some View {
        if router.page == SettingsRouter.general {
            GeneralPage(manager: manager)
        } else if let info = ModuleList.infos.first(where: { $0.id == router.page }) {
            if let module = manager.module(id: info.id) {
                module.makeSettingsView()
                    .id(info.id)
            } else {
                DisabledModulePage(info: info) { manager.setEnabled(info.id, true) }
            }
        }
    }
}

/// 꺼진 기능을 골랐을 때
private struct DisabledModulePage: View {
    let info: EppModuleInfo
    let enable: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: info.symbol).font(.system(size: 40)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(info.name).font(.title2.bold())
            Text(info.summary).foregroundStyle(.secondary)
            Text(L("%@가 꺼져 있어요. 켜면 설정이 여기에 나와요.", info.name)).font(.callout).foregroundStyle(.secondary)
            Button(L("%@ 켜기", info.name), action: enable).keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 일반

private struct GeneralPage: View {
    @ObservedObject var manager: ModuleManager

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showInDock = DockIcon.isOn
    /// "system" | "ko" | "en". 문구는 시작할 때 한 번 정해지므로 바꾸면 다시 열어야 한다.
    @State private var language = UserDefaults.standard.string(forKey: EppLanguage.key) ?? "system"
    private let launchLanguage = UserDefaults.standard.string(forKey: EppLanguage.key) ?? "system"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        Form {
            Section {
                ForEach(ModuleList.infos) { info in
                    Toggle(isOn: Binding(get: { manager.isEnabled(info.id) },
                                         set: { manager.setEnabled(info.id, $0) })) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(info.name)
                                Text(info.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: info.symbol)
                        }
                    }
                    .disabled(manager.soloID != nil)
                }
            } header: {
                Text(L("기능"))
            } footer: {
                Text(manager.soloID != nil
                     ? L("단독 실행 중이라 이 기능만 켜져 있어요.")
                     : L("켠 기능만 실행돼요. 끈 기능은 아무 일도 하지 않고, 단축키도 등록하지 않아요."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("로그인 시 실행"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L("Dock에 아이콘 보이기"), isOn: $showInDock)
                        .onChange(of: showInDock) { _, on in DockIcon.isOn = on }
                    Text(L("켜면 Dock에 Epp가 보이고, 메뉴 막대 왼쪽에 Epp 메뉴가 나와요. 메뉴 막대 아이콘은 그대로 있어요."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker(L("언어"), selection: $language) {
                    Text(L("시스템 설정 따르기")).tag("system")
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
                .onChange(of: language) { _, new in
                    if new == "system" { UserDefaults.standard.removeObject(forKey: EppLanguage.key) }
                    else { UserDefaults.standard.set(new, forKey: EppLanguage.key) }
                }
                if language != launchLanguage {
                    HStack {
                        Text(L("언어를 바꾸면 Epp를 다시 열어야 적용돼요.")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Epp 다시 열기")) { EppApp.relaunch() }
                    }
                }
            }

            Section(L("정보")) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Epp").font(.headline)
                        Text(L("버전 %@", version)).foregroundStyle(.secondary)
                        Text(L("Mac을 편하게 쓰는 작은 기능 모음")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Epp: 로그인 항목 설정 실패 \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
