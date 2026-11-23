import AppKit
import SwiftUI

/// 기능이 쓰는 전역 단축키 하나. 켠 다른 기능과 키가 같으면 그 기능의 단축키 탭 위에 알린다.
public struct EppShortcutInfo: Identifiable, Sendable {
    public let title: String
    /// 화면에 보이는 키 (예: "⌃⌥V")
    public let keys: String
    public var id: String { title + keys }

    public init(title: String, keys: String) {
        self.title = title
        self.keys = keys
    }
}

/// 전역 단축키 한 줄: 이름 · [키 입력 버튼] · 지우기 · 기본값. 모든 기능의 "단축키" 탭이 같은 모양을 쓴다.
/// 버튼을 누르고 키를 누르면 바뀐다. esc는 입력 취소.
public struct EppShortcutRow: View {
    let title: String
    @Binding var combo: KeyCombo?
    let defaultCombo: KeyCombo?
    /// 시스템에 등록하지 못했는지
    let failed: Bool
    /// 새 조합을 받기 전에 확인한다(같은 기능 안에서 겹침 등). 문제가 있으면 알릴 글, 없으면 nil.
    let validate: ((KeyCombo) -> String?)?

    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    public init(_ title: String, combo: Binding<KeyCombo?>, defaultCombo: KeyCombo?, failed: Bool = false,
                validate: ((KeyCombo) -> String?)? = nil) {
        self.title = title
        self.validate = validate
        _combo = combo
        self.defaultCombo = defaultCombo
        self.failed = failed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 8) {
                    if failed {
                        Text(EppText.t("등록하지 못함", "Couldn't register")).font(.caption).foregroundStyle(.red)
                    }
                    Button(recording ? EppText.t("키를 누르세요", "Press keys") : combo?.displayText ?? EppText.t("없음", "None")) {
                        recording ? stop() : start()
                    }
                    .frame(minWidth: 110)
                    Button {
                        stop()
                        combo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(combo == nil)
                    .help(EppText.t("단축키 지우기", "Clear shortcut"))
                    .accessibilityLabel(EppText.t("단축키 지우기", "Clear shortcut"))
                    if let defaultCombo {
                        Button {
                            stop()
                            combo = defaultCombo
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(combo == defaultCombo)
                        .help(EppText.t("기본값(%@)으로", "Back to default (%@)").replacingOccurrences(of: "%@", with: defaultCombo.displayText))
                        .accessibilityLabel(EppText.t("기본값으로", "Restore default"))
                    }
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start() {
        stop()
        recording = true
        HotKey.pauseAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKey.resumeAll() }
        recording = false
        message = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // esc
            stop()
            return
        }
        guard let newCombo = KeyCombo(event: event) else {
            message = EppText.t("⌘, ⌃, ⌥ 중 하나와 함께 누르세요.", "Press it together with ⌘, ⌃ or ⌥.")
            return
        }
        if let problem = validate?(newCombo) {
            message = problem
            return
        }
        combo = newCombo
        stop()
    }
}

/// 단축키 탭 아래쪽의 공통 안내.
public enum EppShortcutText {
    public static var footer: String {
        EppText.t("다른 앱과 겹치면 먼저 등록한 앱이 키를 받아요. 켠 다른 기능과 겹치면 이 탭 위에 알려 줘요.",
                  "If another app uses the same keys, the one that registered first gets them. If another feature you turned on uses them, you'll see a warning above this tab.")
    }
}
