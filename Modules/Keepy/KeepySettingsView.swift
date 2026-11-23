import EppKit
import SwiftUI

/// Epp 설정 창에서 Keepy를 골랐을 때 보이는 화면. 탭: 일반 · 제외 앱 · 단축키
/// (로그인 시 실행, 언어, 업데이트, 정보는 Epp 본체 설정의 "일반"에 있다)
struct KeepySettingsView: View {
    enum Tab: String, CaseIterable {
        case general, ignored, shortcuts

        var title: String {
            switch self {
            case .general: return L("일반")
            case .ignored: return L("제외 앱")
            case .shortcuts: return L("단축키")
            }
        }
    }

    @ObservedObject var settings: AppSettings
    let store: HistoryStore
    // 마지막에 본 탭을 기억해서 다음에 열 때 그 탭부터 보여 준다.
    @AppStorage("keepy.settingsTab") private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("설정"), selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)

            Group {
                switch tab {
                case .general: GeneralTab(settings: settings, store: store)
                case .ignored: IgnoredAppsTab(settings: settings)
                case .shortcuts: ShortcutsTab(settings: settings)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 일반

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let store: HistoryStore

    @State private var trusted = Paster.isTrusted
    @State private var confirmClear = false
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section(L("기록")) {
                Picker(L("보관할 항목 수"), selection: $settings.historyLimit) {
                    ForEach(AppSettings.historyLimits, id: \.self) { Text(L("%ld개", $0)).tag($0) }
                }
                Picker(L("기록 창 위치"), selection: $settings.panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent(L("저장 위치")) {
                    Button(L("Finder에서 보기")) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.directory])
                    }
                }
                Button(L("모든 기록 지우기…"), role: .destructive) { confirmClear = true }
            }

            Section {
                Toggle(L("고르면 바로 붙여 넣기"), isOn: $settings.pasteAutomatically)
                if settings.pasteAutomatically {
                    HStack {
                        Label(trusted ? L("손쉬운 사용 권한 허용됨") : L("손쉬운 사용 권한이 필요해요"),
                              systemImage: trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(trusted ? .green : .orange)
                        Spacer()
                        if !trusted {
                            Button(L("허용하기")) {
                                Paster.requestTrust()
                                Paster.openAccessibilitySettings()
                            }
                        }
                    }
                }
            } header: {
                Text(L("붙여 넣기"))
            } footer: {
                Text(L("끄면 고른 항목을 클립보드에 복사만 하고, ⌘V는 직접 눌러요."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(L("모든 기록을 지울까요?"), isPresented: $confirmClear) {
            Button(L("모두 지우기"), role: .destructive) { store.clear(includingPinned: true) }
            Button(L("취소"), role: .cancel) {}
        } message: {
            Text(L("고정한 항목까지 모두 지워져요. 되돌릴 수 없어요."))
        }
        .onReceive(poll) { _ in trusted = Paster.isTrusted }
    }
}

// MARK: - 제외 앱

private struct IgnoredAppsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.ignoredApps)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 200)
            } header: {
                Text(L("이 앱에서 복사한 내용은 기록하지 않아요"))
            } footer: {
                Text(L("한 줄에 번들 ID 하나씩 적어요. 비밀번호 관리자가 숨김 표시를 붙여 복사한 내용은 앱과 상관없이 기록하지 않아요."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Menu(L("실행 중인 앱에서 더하기")) {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") { add(app.bundleIdentifier) }
                    }
                }
                Button(L("기본값으로")) { settings.ignoredApps = AppSettings.defaultIgnoredApps }
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ bundleID: String?) {
        guard let bundleID, !settings.ignoredBundleIDs.contains(bundleID) else { return }
        let trimmed = settings.ignoredApps.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.ignoredApps = trimmed.isEmpty ? bundleID : trimmed + "\n" + bundleID
    }
}

// MARK: - 단축키

private struct ShortcutsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var runningApps = HotKeyConflicts.runningClipboardApps

    private let panelKeys: [(String, String)] = [
        ("↑ ↓", L("항목 고르기")),
        ("↩", L("붙여 넣기")),
        ("⌥↩", L("서식 없이 붙여 넣기")),
        ("⌘1~9", L("그 번호 항목 바로 붙여 넣기")),
        ("⌘P", L("고정 / 고정 풀기")),
        ("⌘⌫", L("삭제")),
        ("⌘Z", L("삭제 되돌리기")),
        ("esc", L("검색어 지우기 / 닫기")),
    ]

    var body: some View {
        Form {
            Section {
                if !runningApps.isEmpty {
                    Label(L("%@이(가) 켜져 있어요. 같은 단축키를 쓰면 먼저 등록한 앱이 키를 받으니, 겹치지 않게 바꿔 주세요.",
                            runningApps.joined(separator: ", ")), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                LabeledContent(L("클립보드 기록 열기")) {
                    HStack(spacing: 8) {
                        if settings.hotKeyFailed {
                            Text(L("등록하지 못함")).font(.caption).foregroundStyle(.red)
                        }
                        Button(recording ? L("키를 누르세요") : settings.hotKey?.displayText ?? L("없음")) {
                            recording ? stop() : start()
                        }
                        .frame(minWidth: 110)
                        Button {
                            stop()
                            settings.hotKey = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.hotKey == nil)
                        .help(L("단축키 지우기"))
                        .accessibilityLabel(L("단축키 지우기"))
                    }
                }
                HStack {
                    Text(message ?? L("다른 앱과 겹치면 먼저 등록한 앱이 키를 받아요. esc로 입력 취소."))
                        .font(.caption)
                        .foregroundStyle(message == nil ? Color.secondary : Color.red)
                    Spacer()
                    Button(L("기본값으로")) {
                        stop()
                        settings.hotKey = .openHistoryDefault
                    }
                }
            } header: {
                Text(L("전역 단축키"))
            }

            Section(L("기록 창 안에서")) {
                ForEach(panelKeys, id: \.0) { key, action in
                    LabeledContent(action) {
                        Text(key).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            runningApps = HotKeyConflicts.runningClipboardApps
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start() {
        stop()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        message = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // esc
            stop()
            return
        }
        guard let combo = KeyCombo(event: event) else {
            message = L("⌘, ⌃, ⌥ 중 하나와 함께 누르세요.")
            return
        }
        settings.hotKey = combo
        stop()
    }
}
