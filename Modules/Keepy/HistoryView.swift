import SwiftUI

struct HistoryView: View {
    static let size = CGSize(width: 460, height: 540)

    @ObservedObject var vm: PanelViewModel
    let onPick: (ClipItem, Bool) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = vm.visibleItems
        VStack(spacing: 0) {
            searchBar
            Divider()
            if items.isEmpty {
                emptyState
            } else {
                list(items)
            }
            Divider()
            footer(count: items.count)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
        .onAppear { searchFocused = true }
        .onChange(of: vm.focusRequest) { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L("클립보드 기록 검색"), text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("검색어 지우기"))
                .accessibilityLabel(L("검색어 지우기"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: vm.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(vm.query.isEmpty ? L("아직 복사한 항목이 없어요") : L("찾는 항목이 없어요"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipRow(item: item, index: index,
                                isSelected: index == vm.selection, store: vm.store)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                vm.selection = index
                                onPick(item, NSEvent.modifierFlags.contains(.option))
                            }
                            .contextMenu {
                                Button(vm.copyOnly ? L("복사") : L("붙여 넣기")) { onPick(item, false) }
                                Button(vm.copyOnly ? L("서식 없이 복사") : L("서식 없이 붙여 넣기")) { onPick(item, true) }
                                Divider()
                                Button(item.pinned ? L("고정 풀기") : L("고정")) { vm.store.togglePin(item.id) }
                                Button(L("삭제"), role: .destructive) { vm.delete(item) }
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: vm.selection) { _, newValue in
                guard items.indices.contains(newValue) else { return }
                proxy.scrollTo(items[newValue].id)
            }
        }
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: 12) {
            if let notice = vm.notice {
                Text(notice).foregroundStyle(.secondary)
            } else {
                hint("↩", vm.copyOnly ? L("복사") : L("붙여 넣기"))
                hint("⌥↩", L("서식 없이"))
                hint("⌘P", L("고정"))
                hint("⌘⌫", L("삭제"))
            }
            Spacer()
            Text(L("%ld개", count))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key).fontWeight(.semibold)
            Text(label)
        }
        .foregroundStyle(.secondary)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let store: HistoryStore

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: Localization.isKorean ? "ko_KR" : "en_US")
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if let icon = IconCache.appIcon(bundleID: item.sourceBundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                    }
                    Text(subtitle)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help(L("고정"))
                    .accessibilityLabel(L("고정"))
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
        )
        .help(item.tooltip)
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .image:
            if let name = item.imageFile, let thumb = IconCache.thumbnail(at: store.blobURL(name)) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                symbol("photo")
            }
        case .file:
            if let path = item.filePaths.first {
                Image(nsImage: IconCache.fileIcon(path: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                symbol("doc")
            }
        case .text:
            symbol(item.rtfFile == nil ? "text.alignleft" : "doc.richtext")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }

    private var subtitle: String {
        var parts: [String] = []
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(Self.relative.localizedString(for: item.lastUsedAt, relativeTo: Date()))
        parts.append(item.summary)
        return parts.joined(separator: " · ")
    }
}
