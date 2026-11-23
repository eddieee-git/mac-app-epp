import AppKit
import EppKit

/// 기록 목록과 디스크 저장을 맡는다.
/// <Epp 데이터 폴더>/Keepy/history.json + blobs/(이미지·RTF)
@MainActor
final class HistoryStore: ObservableObject {
    /// 최근 사용 순 (0번이 가장 최근)
    @Published private(set) var items: [ClipItem] = []

    let directory: URL
    let blobDirectory: URL
    private let indexURL: URL
    private let limit: () -> Int
    private var pendingSave: DispatchWorkItem?
    /// 방금 삭제한 항목. 되돌릴 수 있도록 파일은 다음 삭제나 `commitDeletion()` 때 지운다.
    private(set) var lastDeleted: (item: ClipItem, index: Int)?

    /// directory: Epp가 정해 준 Keepy 데이터 폴더(점검할 때는 임시 폴더). limit이 없으면 설정의 한도를 쓴다.
    init(directory: URL, limit: (() -> Int)? = nil) {
        self.directory = directory
        self.limit = limit ?? { AppSettings.shared.historyLimit }
        blobDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        indexURL = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - 변경

    func add(_ content: CapturedContent, source: NSRunningApplication?) {
        add(content, sourceBundleID: source?.bundleIdentifier, sourceAppName: source?.localizedName)
    }

    func add(_ content: CapturedContent, sourceBundleID: String?, sourceAppName: String?) {
        let now = Date()
        if let index = items.firstIndex(where: { $0.contentHash == content.hash }) {
            // 같은 내용을 다시 복사하면 맨 위로 올린다.
            var existing = items.remove(at: index)
            existing.lastUsedAt = now
            if existing.kind == .text, existing.text != content.text {
                // 빈칸만 다른 글이면 방금 복사한 쪽으로 바꿔 둔다.
                existing.text = content.text
                if let old = existing.rtfFile { try? FileManager.default.removeItem(at: blobURL(old)) }
                existing.rtfFile = content.rtfData.flatMap { writeBlob($0, name: "\(existing.id.uuidString).rtf") }
            }
            items.insert(existing, at: 0)
            scheduleSave()
            return
        }

        let id = UUID()
        var item = ClipItem(
            id: id, kind: content.kind, text: content.text,
            rtfFile: nil, imageFile: nil, filePaths: content.filePaths,
            detail: content.detail,
            sourceBundleID: sourceBundleID, sourceAppName: sourceAppName,
            createdAt: now, lastUsedAt: now, pinned: false, contentHash: content.hash
        )
        if let png = content.pngData {
            item.imageFile = writeBlob(png, name: "\(id.uuidString).png")
        }
        if let rtf = content.rtfData {
            item.rtfFile = writeBlob(rtf, name: "\(id.uuidString).rtf")
        }
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    func markUsed(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.lastUsedAt = Date()
        items.insert(item, at: 0)
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        trim()
        scheduleSave()
    }

    /// 하나 삭제. `undoDelete()`로 되돌릴 수 있다.
    func delete(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        commitDeletion()
        lastDeleted = (items.remove(at: index), index)
        scheduleSave()
    }

    @discardableResult
    func undoDelete() -> ClipItem? {
        guard let (item, index) = lastDeleted else { return nil }
        lastDeleted = nil
        items.insert(item, at: min(index, items.count))
        scheduleSave()
        return item
    }

    /// 되돌리기를 더 이상 받지 않고, 삭제한 항목의 파일을 지운다.
    func commitDeletion() {
        if let (item, _) = lastDeleted { removeBlobs(of: item) }
        lastDeleted = nil
    }

    func clear(includingPinned: Bool) {
        commitDeletion()
        let removed = items.filter { includingPinned || !$0.pinned }
        removed.forEach(removeBlobs)
        items.removeAll { includingPinned || !$0.pinned }
        scheduleSave()
    }

    /// 고정하지 않은 항목이 한도를 넘으면 오래된 것부터 지운다.
    func trim() {
        let limit = limit()
        var unpinned = 0
        var kept: [ClipItem] = []
        for item in items {
            if item.pinned { kept.append(item); continue }
            unpinned += 1
            if unpinned > limit { removeBlobs(of: item) } else { kept.append(item) }
        }
        if kept.count != items.count {
            items = kept
            scheduleSave()
        }
    }

    // MARK: - 파일

    func blobURL(_ name: String) -> URL {
        blobDirectory.appendingPathComponent(name)
    }

    func blobData(_ name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: blobURL(name))
    }

    private func writeBlob(_ data: Data, name: String) -> String? {
        do {
            try data.write(to: blobURL(name), options: .atomic)
            return name
        } catch {
            EppLog.error("클립보드", "파일 저장 실패 \(error)")
            return nil
        }
    }

    private func removeBlobs(of item: ClipItem) {
        for name in [item.imageFile, item.rtfFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: blobURL(name))
        }
    }

    // MARK: - 저장

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            items = try decoder.decode([ClipItem].self, from: data)
        } catch {
            EppLog.error("클립보드", "기록을 읽지 못함 \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            EppLog.error("클립보드", "기록 저장 실패 \(error)")
        }
    }
}
