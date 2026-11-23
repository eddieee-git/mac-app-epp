import SwiftUI

/// 기능 설정 화면의 탭 하나. 내용은 `Form`으로 만든다(스타일은 페이지가 `.grouped`로 맞춘다).
///
/// - 탭 순서 규칙: **일반** · (기능 고유 탭) · **단축키**. 탭 id는 저장되므로 바꾸지 않는다.
/// - `keywords`: 설정 창 왼쪽 위 검색에서 이 탭을 찾게 할 설정 이름들. 화면에 보이는 `L("…")` 문구를 그대로 넣는다.
public struct EppSettingsTab: Identifiable {
    public let id: String
    public let title: String
    public let keywords: [String]
    public let content: AnyView

    public init<Content: View>(_ id: String, _ title: String, keywords: [String] = [],
                               @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.content = AnyView(content())
    }
}

/// 설정 창이 기억하는 값의 이름. 본체(검색, 시작 안내)와 페이지가 같이 쓴다.
public enum EppSettingsKeys {
    /// 기능 설정에서 마지막에 본 탭
    public static func tab(_ moduleID: String) -> String { "\(moduleID).settingsTab" }
    /// 시작하기 상자를 닫았는지
    public static func gettingStartedHidden(_ moduleID: String) -> String { "\(moduleID).gettingStartedHidden" }
}

/// 모든 기능이 같은 모양으로 보이는 설정 화면:
/// 머리(아이콘·이름·설명) → 시작하기 상자(닫기 전까지) → 위쪽 탭 → 고른 탭의 Form.
/// 기능은 `settingsTabs()`와 `makeGettingStarted()`로 내용만 넘기고, 이 틀은 Epp 본체가 그린다.
public struct EppSettingsPage: View {
    let info: EppModuleInfo
    let tabs: [EppSettingsTab]
    let gettingStarted: AnyView?
    @AppStorage private var selected: String
    @AppStorage private var gettingStartedHidden: Bool

    public init(info: EppModuleInfo, tabs: [EppSettingsTab], gettingStarted: AnyView?) {
        self.info = info
        self.tabs = tabs
        self.gettingStarted = gettingStarted
        _selected = AppStorage(wrappedValue: tabs.first?.id ?? "", EppSettingsKeys.tab(info.id))
        _gettingStartedHidden = AppStorage(wrappedValue: false, EppSettingsKeys.gettingStartedHidden(info.id))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: info.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.name).font(.title3.bold())
                    Text(info.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            if let gettingStarted, !gettingStartedHidden {
                // GroupBox는 안의 긴 글을 폭 없이 재서 한 글자씩 줄을 바꿔 아주 길어진 적이 있다. 폭이 정해진 상자를 직접 그린다.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(EppText.t("시작하기", "Getting Started")).bold()
                        Spacer()
                        Button(EppText.t("닫기", "Close")) { gettingStartedHidden = true }
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                    gettingStarted
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            if tabs.count > 1 {
                Picker("", selection: $selected) {
                    ForEach(tabs) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.bottom, 4)
            }

            // Form은 이 창 안에서 내용 높이만큼 커지려 한다. 그대로 두면 창보다 길어져 창 전체(왼쪽 목록까지)가
            // 위로 밀린다. 남은 자리를 먼저 정하고(Color.clear) 그 안에 Form을 얹어서, 넘치면 Form 안에서 스크롤하게 한다.
            Color.clear
                .overlay(alignment: .top) {
                    (tabs.first { $0.id == selected } ?? tabs.first)?.content
                        .formStyle(.grouped)
                }
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 시작하기 상자 안의 단계 목록. 끝낸 단계는 초록 체크로 바뀐다. 모든 기능이 이 모양을 쓴다.
public struct EppStepList: View {
    public struct Step {
        public let text: String
        public let done: Bool
        /// 끝내지 않은 단계 오른쪽에 붙일 버튼 (예: "권한 열기")
        public let action: (title: String, run: () -> Void)?
        public init(_ text: String, done: Bool, action: (title: String, run: () -> Void)? = nil) {
            self.text = text
            self.done = done
            self.action = action
        }
    }

    let steps: [Step]
    let footer: String?

    public init(_ steps: [Step], footer: String? = nil) {
        self.steps = steps
        self.footer = footer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 10) {
                    Image(systemName: step.done ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .foregroundStyle(step.done ? .green : .secondary)
                        .font(.title3)
                        .accessibilityLabel(step.done ? EppText.t("끝냄", "Done") : "\(index + 1)")
                    Text(step.text)
                        .foregroundStyle(step.done ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !step.done, let action = step.action {
                        Button(action.title, action: action.run).controlSize(.small)
                    }
                }
            }
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 권한 한 줄. 모든 기능이 같은 모양: 허용됨 초록 / 필요 주황, 필요하면 오른쪽에 "허용하기"와 덧붙일 버튼.
public struct EppPermissionRow<Extra: View>: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void
    let extra: Extra

    public init(title: String, detail: String, granted: Bool, request: @escaping () -> Void,
                @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.detail = detail
        self.granted = granted
        self.request = request
        self.extra = extra()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .accessibilityLabel(granted ? EppText.t("허용됨", "Allowed") : EppText.t("필요해요", "Needed"))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button(EppText.t("허용하기", "Allow"), action: request)
                extra
            }
        }
    }
}

public extension EppPermissionRow where Extra == EmptyView {
    init(title: String, detail: String, granted: Bool, request: @escaping () -> Void) {
        self.init(title: title, detail: detail, granted: granted, request: request) { EmptyView() }
    }
}

/// EppKit 안의 짧은 공통 문구(사전 없이 두 언어를 바로 적는다).
public enum EppText {
    public static func t(_ ko: String, _ en: String) -> String { EppLanguage.isKorean ? ko : en }
}
