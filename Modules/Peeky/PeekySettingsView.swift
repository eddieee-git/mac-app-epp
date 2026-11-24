import EppKit
import SwiftUI

/// Epp 설정 창에서 Peeky를 골랐을 때의 탭: 일반 · 아이콘 · 그룹 · 단축키.
/// 틀(머리·시작하기·탭·검색)은 Epp 본체가 그린다. 로그인 시 실행, 언어, 업데이트, 정보는 Epp 일반 쪽에 있다.
enum PeekySettings {
    @MainActor
    static func tabs() -> [EppSettingsTab] {
        [
            EppSettingsTab("general", L("일반"), keywords: [
                L("메뉴바 정리"), L("다시 정리"),
                L("바 아이콘을 오른쪽 끝으로 옮기기"),
            ]) { PeekySettingsView(tab: .general) },
            EppSettingsTab("icons", L("아이콘"), keywords: [
                L("메뉴바 아이콘"), L("보이기"), L("숨기기"), L("「숨기기」 아이콘을 메뉴바에서 숨기기"), L("항목 검색"),
            ]) { PeekySettingsView(tab: .icons) },
            EppSettingsTab("groups", L("그룹"), keywords: [
                L("그룹 추가"), L("아이콘 바 모양"), L("줄 수"), L("바 최대 너비"), L("순서 초기화"),
            ]) { PeekySettingsView(tab: .groups) },
            EppSettingsTab("shortcuts", L("단축키"), keywords: [
                L("전역 단축키"), L("보조 키"),
            ]) { PeekySettingsView(tab: .shortcuts) },
        ]
    }
}

/// 설정 맨 위 시작하기 상자. 끝낸 단계는 체크로 바뀐다.
struct PeekyGettingStarted: View {
    let openPermissions: () -> Void
    @ObservedObject private var store = ItemStore.shared
    @ObservedObject private var prefs: Preferences = Preferences.shared
    @State private var axTrusted = AX.isTrusted
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        EppStepList([
            .init(L("손쉬운 사용 권한 허용하기 (Epp 설정 → 일반 → 권한)"), done: axTrusted,
                  action: (L("권한 열기"), openPermissions)),
            .init(L("아이콘 탭에서 숨길 아이콘을 「숨기기」로 고르기"),
                  done: store.items.contains { !$0.isFixed && prefs.group(for: $0.id) != nil }),
        ], footer: L("숨기기를 고르면 그 아이콘이 메뉴바에서 빠져요. 메뉴바의 그룹 아이콘을 누르면 숨긴 아이콘이 바에 모여 있어요."))
        .onReceive(poll) { _ in axTrusted = AX.isTrusted }
    }
}

struct PeekySettingsView: View {
    enum Tab { case general, icons, groups, shortcuts }

    let tab: Tab
    @ObservedObject private var store = ItemStore.shared
    @ObservedObject private var prefs: Preferences = Preferences.shared
    @State private var axTrusted = AX.isTrusted
    @State private var search = ""
    /// 메뉴바에서 안 보이는 Peeky 그룹 아이콘 이름들.
    @State private var hiddenIcons: [String] = []

    /// 권한·아이콘 가려짐은 Epp가 앞으로 올 때 바로 다시 보고, 그 밖에는 가끔만 확인한다.
    private let poll = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init(tab: Tab) { self.tab = tab }

    var body: some View {
        Form {
            switch tab {
            case .general:
                if !hiddenIcons.isEmpty { hiddenIconSection }
                menuBarSection
            case .icons:
                itemsSection
            case .groups:
                groupsSection
                barSection
            case .shortcuts:
                shortcutsSection
            }
        }
        .onAppear {
            store.refresh(full: true)
            hiddenIcons = StatusIconCheck.hiddenGroupNames()
        }
        .onReceive(poll) { _ in recheck() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in recheck() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in recheck() }
        .onReceive(store.$items) { _ in
            let hidden = StatusIconCheck.hiddenGroupNames()
            if hidden != hiddenIcons { hiddenIcons = hidden }
        }
    }

    private func recheck() {
        let hidden = StatusIconCheck.hiddenGroupNames()
        if hidden != hiddenIcons { hiddenIcons = hidden }
        let nowTrusted = AX.isTrusted
        if nowTrusted != axTrusted {
            axTrusted = nowTrusted
            store.refresh(full: true)
        }
    }

    // MARK: Sections

    private var hiddenIconSection: some View {
        Section {
            Label(L("바 아이콘이 메뉴바에서 안 보여요 (%@)", hiddenIcons.joined(separator: ", ")),
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(prefs.hotKeyModifiers == .off
                 ? L("노치에 가려졌거나 메뉴바에 자리가 없어요. ⌘를 누른 채 다른 아이콘을 왼쪽으로 옮겨 자리를 만들고, 바 아이콘은 오른쪽 끝으로 옮겨 두세요. 그래도 안 보이면 시스템 설정 → 메뉴 막대에서 Epp가 켜져 있는지 확인하세요.")
                 : L("노치에 가려졌거나 메뉴바에 자리가 없어요. 단축키 %@1로 바를 열 수 있어요. ⌘를 누른 채 다른 아이콘을 왼쪽으로 옮겨 자리를 만들고, 바 아이콘은 오른쪽 끝으로 옮겨 두세요. 그래도 안 보이면 시스템 설정 → 메뉴 막대에서 Epp가 켜져 있는지 확인하세요.", prefs.hotKeyModifiers.symbol))
                .font(.callout).foregroundStyle(.secondary)
            Button(L("바 아이콘을 오른쪽 끝으로 옮기기")) { StatusIconCheck.resetPositions() }
        }
    }

    /// 그룹을 여는 단축키: 보조 키 하나를 고르면 B는 첫 그룹, 1~9는 각 그룹.
    private var shortcutsSection: some View {
        Section {
            Picker(L("보조 키"), selection: $prefs.hotKeyModifiers) {
                ForEach(HotKeyModifiers.allCases) { Text($0.title).tag($0) }
            }
            if prefs.hotKeyModifiers != .off {
                if !prefs.groups.isEmpty {
                    LabeledContent(L("첫 그룹 열기")) {
                        Text("\(prefs.hotKeyModifiers.symbol)B").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(prefs.groups.prefix(9).enumerated()), id: \.element.id) { index, group in
                    LabeledContent(L("%@ 열기", group.name)) {
                        Text("\(prefs.hotKeyModifiers.symbol)\(index + 1)").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(L("전역 단축키"))
        } footer: {
            Text(L("보조 키 하나를 고르면 B는 첫 그룹, 1~9는 각 그룹 바를 열어요.") + " " + EppShortcutText.footer)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var barSection: some View {
        Section(L("아이콘 바 모양")) {
            Picker(L("줄 수"), selection: $prefs.rowCount) {
                Text(L("한 줄")).tag(1)
                Text(L("두 줄")).tag(2)
                Text(L("세 줄")).tag(3)
            }
            .pickerStyle(.segmented)
            LabeledContent(L("바 최대 너비")) {
                HStack {
                    Slider(value: $prefs.maxStripWidth, in: 120...900, step: 20)
                        .frame(width: 180)
                    Text("\(Int(prefs.maxStripWidth))pt").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            LabeledContent(L("바 안의 순서")) {
                Button(L("순서 초기화")) { prefs.itemOrder = [] }
                    .disabled(prefs.itemOrder.isEmpty)
                    .help(L("바에서 끌어 바꾼 순서를 메뉴바 순서로 되돌려요"))
            }
        }
    }

    private var menuBarSection: some View {
        Section {
            LabeledContent(L("아이콘 자리가 고른 대로가 아니면")) {
                Button(L("다시 정리")) { StatusIconCheck.arrange() }
                    .disabled(!prefs.hideInMenuBar)
            }
            LabeledContent(L("바 아이콘이 안 보이면")) {
                Button(L("바 아이콘을 오른쪽 끝으로 옮기기")) { StatusIconCheck.resetPositions() }
            }
        } header: {
            Text(L("메뉴바 정리"))
        } footer: {
            Text(L("메뉴바에서 숨기기를 켜면 › 버튼이 생겨요. › 오른쪽 아이콘은 늘 보이고, 왼쪽 아이콘은 숨겨져요. ‹ ›를 누르면 잠깐 펼치거나 다시 숨겨요. 노치 뒤에 있어 잡을 수 없는 아이콘은 옮기지 못해요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var groupsSection: some View {
        Section {
            ForEach(Array(prefs.groups.enumerated()), id: \.element.id) { index, group in
                groupRow(group, index: index)
            }
        } header: {
            HStack {
                Text(L("그룹"))
                Spacer()
                Button { prefs.addGroup() } label: { Label(L("그룹 추가"), systemImage: "plus") }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        } footer: {
            Text(L("그룹마다 메뉴바에 아이콘이 하나씩 생기고, 누르면 그 그룹의 항목만 바에 보여요. ⋯에서 그룹마다 줄 수와 표시 방식을 따로 정할 수 있어요."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("그룹은 아이콘 바에 보일 항목만 정해요. 메뉴바에서도 빼려면 「메뉴바 정리」에서 숨기기를 켜세요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        Section {
            Toggle(isOn: $prefs.hideInMenuBar) {
                Text(L("「숨기기」 아이콘을 메뉴바에서 숨기기"))
                Text(L("아이콘을 처음 「숨기기」로 고르면 저절로 켜져요. 정리하는 동안 마우스가 잠깐 움직여요. 끄면 숨긴 아이콘도 메뉴바에 다시 보여요."))
            }
        }
        Section {
            Text(L("아이콘마다 오른쪽에서 고르세요. 「보이기」는 메뉴바에 그대로 두고, 「숨기기」는 메뉴바에서 빼서, 메뉴바의 그룹 아이콘을 누르면 열리는 바에 모아요."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            // 목록을 거르는 검색. 창 전체 검색(왼쪽 위)과 따로, 이 목록 바로 위에 둔다.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(L("항목 검색"), text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .accessibilityLabel(L("검색어 지우기"))
                }
            }
            if !axTrusted {
                Text(L("손쉬운 사용 권한을 주면 항목 목록이 여기에 나타나요.")).foregroundStyle(.secondary)
            } else if filteredItems.isEmpty {
                Text(L("찾은 항목이 없어요.")).foregroundStyle(.secondary)
            } else {
                ForEach(filteredItems) { item in itemRow(item) }
            }
        } header: {
            HStack {
                Text(L("메뉴바 아이콘"))
                Spacer()
                Menu(L("모두")) {
                    Button(L("모두 보이기")) { filteredItems.forEach { prefs.assign($0.id, to: nil) } }
                    ForEach(prefs.groups) { group in
                        Button(prefs.groups.count == 1 ? L("모두 숨기기") : L("모두 숨기기 · %@", group.name)) {
                            filteredItems.filter { !$0.isFixed }.forEach { prefs.assign($0.id, to: group.id) }
                        }
                    }
                }
                .fixedSize()
                Button { store.refresh(full: true) } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("새로고침"))
            }
            .buttonStyle(.borderless)
            .font(.callout)
        } footer: {
            Text(L("「보이기」는 메뉴바에 그대로 둬요. 「숨기기」는 메뉴바에서 빼고 아이콘 바에 모아요. 바 아이콘을 누르면 바가 열리고, 바에서 누르면 원래 메뉴가 열려요."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("자리가 모자라면 macOS는 왼쪽 아이콘부터 숨겨요. 꼭 보여야 하는 「보이기」 아이콘은 오른쪽 클릭 → 맨 오른쪽으로 옮기기를 고르세요."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filteredItems: [MenuBarItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.items }
        return store.items.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }

    // MARK: Rows

    @ViewBuilder
    private func groupRow(_ group: ItemGroup, index: Int) -> some View {
        HStack(spacing: 10) {
            Picker("", selection: Binding(get: { group.symbol },
                                          set: { symbol in editGroup(group.id) { $0.symbol = symbol } })) {
                ForEach(ItemGroup.symbols, id: \.self) { Image(systemName: $0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            TextField("", text: Binding(get: { group.name },
                                        set: { name in editGroup(group.id) { $0.name = name } }),
                      prompt: Text(L("그룹 이름")))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Text(L("%ld개", store.items.filter { !$0.isFixed && prefs.group(for: $0.id) == group.id }.count))
                .monospacedDigit().foregroundStyle(.secondary)
            if prefs.hotKeyModifiers != .off, index < 9 {
                Text("\(prefs.hotKeyModifiers.symbol)\(index + 1)").font(.caption).foregroundStyle(.secondary)
            }
            groupOptionsMenu(group)
            Button { prefs.removeGroup(group.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(prefs.groups.count <= 1)
                .help(prefs.groups.count <= 1 ? L("그룹은 하나 이상 있어야 해요") : L("그룹 삭제 (항목은 첫 그룹으로 이동)"))
        }
    }

    private func groupOptionsMenu(_ group: ItemGroup) -> some View {
        Menu {
            Picker(L("줄 수"), selection: Binding(get: { group.rowCount ?? 0 },
                                                set: { value in editGroup(group.id) { $0.rowCount = value == 0 ? nil : value } })) {
                Text(L("전체 설정 따르기")).tag(0)
                Text(L("한 줄")).tag(1)
                Text(L("두 줄")).tag(2)
                Text(L("세 줄")).tag(3)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("이 그룹만의 설정"))
    }

    private func editGroup(_ id: UUID, _ change: (inout ItemGroup) -> Void) {
        guard var group = prefs.groups.first(where: { $0.id == id }) else { return }
        change(&group)
        prefs.updateGroup(group)
    }

    @ViewBuilder
    private func itemRow(_ item: MenuBarItem) -> some View {
        itemRowContent(item)
            .contextMenu {
                if !item.isFixed, prefs.group(for: item.id) == nil {
                    Button(L("맨 오른쪽으로 옮기기 (가장 오래 보이게)")) { StatusIconCheck.bringToFront(item.id) }
                }
            }
    }

    @ViewBuilder
    private func itemRowContent(_ item: MenuBarItem) -> some View {
        HStack(spacing: 10) {
            itemIcon(item).frame(width: 40, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label).lineLimit(1)
                if item.label != item.appName {
                    Text(item.appName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let status = status(of: item) {
                Text(status.text)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                    .help(status.help)
            }
            if item.isFixed {
                Text(L("항상 보임")).foregroundStyle(.secondary)
                    .help(L("macOS가 이 아이콘은 옮기지 못하게 해서 늘 메뉴바에 보여요."))
            } else if prefs.groups.count == 1 {
                placementPicker(item).pickerStyle(.segmented).fixedSize()
            } else {
                placementPicker(item).pickerStyle(.menu).fixedSize()
            }
        }
    }

    /// 아이콘마다 「보이기」 또는 「숨기기(· 그룹)」
    private func placementPicker(_ item: MenuBarItem) -> some View {
        Picker("", selection: Binding(get: { prefs.group(for: item.id) },
                                      set: { prefs.assign(item.id, to: $0) })) {
            Text(L("보이기")).tag(UUID?.none)
            ForEach(prefs.groups) { group in
                Text(prefs.groups.count == 1 ? L("숨기기") : L("숨기기 · %@", group.name)).tag(Optional(group.id))
            }
        }
        .labelsHidden()
    }

    private func status(of item: MenuBarItem) -> (text: String, help: String)? {
        item.status(hiding: prefs.hideInMenuBar, unmovable: store.unmovableIDs.contains(item.id))
    }

    @ViewBuilder
    private func itemIcon(_ item: MenuBarItem) -> some View {
        if let image = store.trimmedImage(for: item) {
            Image(nsImage: image).resizable().renderingMode(image.isTemplate ? .template : .original)
                .aspectRatio(contentMode: .fit)
        } else if let icon = item.appIcon {
            Image(nsImage: icon).resizable().renderingMode(icon.isTemplate ? .template : .original)
                .aspectRatio(contentMode: .fit).padding(icon.isTemplate ? 2 : 0)
        } else {
            Image(systemName: "app")
        }
    }
}
