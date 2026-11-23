import Combine
import Foundation

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    @Published var selection = 0
    /// 글 항목을 새 스티커로 만든다. 스티커 기능이 꺼져 있으면 false(메뉴에 안 보임 대신 알림).
    var makeSticky: ((ClipItem) -> Bool)?
    /// 값이 바뀌면 검색창에 다시 포커스를 준다.
    @Published private(set) var focusRequest = 0
    /// 아래 줄에 잠깐 보여 줄 알림 (예: 삭제했어요 · ⌘Z 되돌리기)
    @Published private(set) var notice: String?
    /// 앱 아이콘으로 열었을 때: 고르면 클립보드에 올리기만 한다(붙여 넣을 앞 앱이 없음).
    @Published var copyOnly = false

    let store: HistoryStore
    private var cancellable: AnyCancellable?
    private var noticeWork: DispatchWorkItem?

    init(store: HistoryStore) {
        self.store = store
        cancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// 고정 항목을 먼저, 나머지는 최근 사용 순
    var visibleItems: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let base = q.isEmpty ? store.items : store.items.filter { $0.matches(q) }
        return base.filter(\.pinned) + base.filter { !$0.pinned }
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.indices.contains(selection) ? items[selection] : nil
    }

    func prepareForShow() {
        query = ""
        selection = 0
        notice = nil
        focusRequest += 1
    }

    func move(by delta: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func delete(_ item: ClipItem) {
        store.delete(item.id)
        selection = min(selection, max(visibleItems.count - 1, 0))
        show(L("삭제했어요 · ⌘Z 되돌리기"))
    }

    func deleteSelected() {
        if let item = selectedItem { delete(item) }
    }

    func undoDelete() {
        guard let item = store.undoDelete() else { return }
        if let index = visibleItems.firstIndex(where: { $0.id == item.id }) { selection = index }
        show(L("되돌렸어요"))
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        store.togglePin(item.id)
        if let index = visibleItems.firstIndex(where: { $0.id == item.id }) {
            selection = index
        }
    }

    private func show(_ text: String) {
        notice = text
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.notice = nil }
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
