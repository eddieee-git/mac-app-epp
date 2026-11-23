import AppKit
import EppKit
import SwiftUI

/// 처음 실행할 때 보여 주는 안내: 손쉬운 사용 권한, 단축키, 쓰는 방법. 메뉴바의 '시작 안내'로 다시 열 수 있다.
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    /// "설정 열기" 버튼: Epp 설정 창에서 Keepy를 연다.
    var openSettings: () -> Void = {}

    func close() { window?.close() }

    func show() {
        if window == nil {
            let view = WelcomeView(close: { [weak self] in self?.window?.close() },
                                   openSettings: { [weak self] in self?.openSettings() })
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = .preferredContentSize
            let w = EscClosableWindow(contentViewController: controller)
            w.styleMask = [.titled, .closable]
            w.title = L("Keepy 시작 안내")
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        // SwiftUI 내용의 크기가 정해진 뒤에 가운데로 옮긴다. 먼저 옮기면 작은 크기 기준으로 잡혀 한쪽으로 치우친다.
        window.layoutIfNeeded()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let close: () -> Void
    let openSettings: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @State private var trusted = Paster.isTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: KeepyModule.info.symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Keepy에 오신 걸 환영해요")).font(.title2.bold())
                    Text(L("복사한 내용을 모아 두었다가 언제든 다시 붙여 넣는 메뉴바 앱이에요.")).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("1. 손쉬운 사용 권한")).bold()
                        Text(trusted ? L("켜져 있어요. 고른 항목을 앞에 있던 앱에 바로 붙여 넣어요.")
                                     : L("고른 항목을 바로 붙여 넣으려면 필요해요. 없어도 클립보드에 복사는 돼요. 업데이트한 뒤라면 이미 켜져 있어도 한 번 껐다 켜야 할 수 있어요."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !trusted {
                        Button(L("허용하기")) {
                            Paster.requestTrust()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("2. 단축키")).bold()
                    HStack {
                        Text(L("클립보드 기록 열기"))
                        Spacer()
                        Text(settings.hotKey?.displayText ?? L("없음"))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("3. 쓰는 방법")).bold()
                    Text(L("• 평소처럼 복사하면 Keepy가 기록해 둬요."))
                    Text(L("• 단축키로 기록을 열고, 입력해서 찾고, ↩로 붙여 넣어요."))
                    Text(L("• ⌘1~9로 바로 고르고, ⌘P로 자주 쓰는 항목을 맨 위에 고정해요."))
                    Text(L("• 비밀번호 관리자에서 복사한 내용은 기록하지 않아요."))
                    Text(L("• 메뉴바에 Epp 아이콘이 안 보이면 시스템 설정 → 메뉴 막대에서 Epp를 켜 주세요."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
                .padding(4)
            }

            HStack {
                Toggle(L("다음부터 열지 않기"), isOn: Binding(get: { !settings.showWelcome },
                                                      set: { settings.showWelcome = !$0 }))
                Spacer()
                Button(L("설정 열기"), action: openSettings)
                Button(L("시작하기"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onReceive(timer) { _ in trusted = Paster.isTrusted }
    }
}
