import EppKit
import SwiftUI

/// Epp 설정 창에서 Keepy를 골랐을 때의 탭: 일반 · 제외 앱 · 단축키.
/// 틀(머리·시작하기·탭·검색)은 Epp 본체가 그린다. 로그인 시 실행, 언어, 업데이트, 정보는 Epp 일반 쪽에 있다.
enum KeepySettings {
    @MainActor
    static func tabs(settings: AppSettings, store: HistoryStore) -> [EppSettingsTab] {
        [
            EppSettingsTab("general", L("일반"), keywords: [
                L("기록"), L("보관할 항목 수"), L("오래된 기록 지우기"), L("기록 창 위치"),
                L("모든 기록 지우기…"), L("붙여 넣기"), L("고르면 바로 붙여 넣기"),
            ]) { GeneralTab(settings: settings, store: store) },
            EppSettingsTab("ignored", L("제외 앱"), keywords: [
                L("이 앱에서 복사한 내용은 기록하지 않아요"), L("실행 중인 앱에서 더하기"),
            ]) { IgnoredAppsTab(settings: settings) },
            EppSettingsTab("shortcuts", L("단축키"), keywords: [
                L("클립보드 기록 열기"), L("전역 단축키"), L("기록 창 안에서"),
            ]) { ShortcutsTab(settings: settings) },
        ]
    }
}

/// 설정 맨 위 시작하기 상자. 끝낸 단계는 체크로 바뀐다.
struct KeepyGettingStarted: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: HistoryStore
    let openPermissions: () -> Void
    @State private var trusted = Paster.isTrusted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        EppStepList([
            .init(L("손쉬운 사용 권한 허용하기 (Epp 설정 → 일반 → 권한)"), done: trusted || !settings.pasteAutomatically,
                  action: (L("권한 열기"), openPermissions)),
            .init(L("평소처럼 복사하기. Epp가 기록해 둬요."), done: !store.items.isEmpty),
            .init(L("%@로 기록을 열고 ↩로 붙여 넣기", settings.hotKey?.displayText ?? L("메뉴")), done: settings.hasPasted),
        ], footer: L("⌘1~9로 바로 고르고, ⌘P로 자주 쓰는 항목을 맨 위에 고정해요. 비밀번호 관리자에서 복사한 내용은 기록하지 않아요."))
        .onReceive(poll) { _ in trusted = Paster.isTrusted }
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
            Section {
                Picker(L("보관할 항목 수"), selection: $settings.historyLimit) {
                    ForEach(AppSettings.historyLimits, id: \.self) { Text(L("%ld개", $0)).tag($0) }
                }
                Picker(L("오래된 기록 지우기"), selection: $settings.historyMaxAgeDays) {
                    ForEach(AppSettings.historyMaxAges, id: \.self) { days in
                        Text(days == 0 ? L("지우지 않음") : L("%ld일 지나면", days)).tag(days)
                    }
                }
                Picker(L("기록 창 위치"), selection: $settings.panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                }
                Button(L("모든 기록 지우기…"), role: .destructive) { confirmClear = true }
            } header: {
                Text(L("기록"))
            } footer: {
                Text(L("기록은 암호화해서 이 Mac에만 저장해요. 고정한 항목은 날짜가 지나도 지우지 않아요."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("고르면 바로 붙여 넣기"), isOn: $settings.pasteAutomatically)
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

/// 단축키 탭: 전역 단축키(공통 EppShortcutRow) → 기록 창 안에서. 모든 기능이 같은 순서.
private struct ShortcutsTab: View {
    @ObservedObject var settings: AppSettings
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
                EppShortcutRow(L("클립보드 기록 열기"), combo: $settings.hotKey,
                               defaultCombo: .openHistoryDefault, failed: settings.hotKeyFailed)
            } header: {
                Text(L("전역 단축키"))
            } footer: {
                Text(EppShortcutText.footer).font(.caption).foregroundStyle(.secondary)
            }

            Section(L("기록 창 안에서")) {
                ForEach(panelKeys, id: \.0) { key, action in
                    LabeledContent(action) {
                        Text(key).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            runningApps = HotKeyConflicts.runningClipboardApps
        }
    }
}
