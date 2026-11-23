import AppKit
import EppKit

/// 기록 목록과 디스크 저장을 맡는다.
/// <Epp 데이터 폴더>/Keepy/history.json + blobs/(이미지·RTF). 모두 암호화해서 쓴다(`EppCrypto`, 키는 키체인).
/// 예전 평문 파일은 그대로 읽고, 다음에 저장할 때 암호화한다.
@MainActor
final class HistoryStore: ObservableObject {
    /// 최근 사용 순 (0번이 가장 최근)
    @Published private(set) var items: [ClipItem] = []

    let directory: URL
    let blobDirectory: URL
    private let indexURL: URL
    private let limit: () -> Int
    /// 고정하지 않은 항목을 며칠 지나면 지울지(0이면 지우지 않음)
    private let maxAgeDays: () -> Int
    private let crypto: EppCrypto
    /// 기록 파일을 읽지 못했으면(키를 잃는 등) 저장하기 전에 그 파일을 옆으로 옮겨 남긴다.
    private var unreadableIndex = false
    private var pendingSave: DispatchWorkItem?
    /// 방금 삭제한 항목. 되돌릴 수 있도록 파일은 다음 삭제나 `commitDeletion()` 때 지운다.
    private(set) var lastDeleted: (item: ClipItem, index: Int)?

    /// directory: Epp가 정해 준 Keepy 데이터 폴더(점검할 때는 임시 폴더). limit이 없으면 설정의 한도를 쓴다.
    init(directory: URL, limit: (() -> Int)? = nil, maxAgeDays: (() -> Int)? = nil,
         crypto: EppCrypto = EppCrypto(account: "keepy-history")) {
        self.directory = directory
        self.limit = limit ?? { AppSettings.shared.historyLimit }
        self.maxAgeDays = maxAgeDays ?? { AppSettings.shared.historyMaxAgeDays }
        self.crypto = crypto
        blobDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        indexURL = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        load()
        trim()
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

    /// 고정하지 않은 항목이 한도를 넘거나 정한 날짜보다 오래되면 지운다.
    func trim(now: Date = Date()) {
        let limit = limit()
        let days = maxAgeDays()
        let cutoff = days > 0 ? now.addingTimeInterval(-Double(days) * 86_400) : nil
        var unpinned = 0
        var kept: [ClipItem] = []
        for item in items {
            if item.pinned { kept.append(item); continue }
            unpinned += 1
            let tooOld = cutoff.map { item.lastUsedAt < $0 } ?? false
            if unpinned > limit || tooOld { removeBlobs(of: item) } else { kept.append(item) }
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
        guard let name, let data = try? Data(contentsOf: blobURL(name)) else { return nil }
        do {
            return try crypto.decrypt(data)
        } catch {
            EppLog.error("클립보드", "파일을 풀지 못함 \(error)")
            return nil
        }
    }

    private func writeBlob(_ data: Data, name: String) -> String? {
        do {
            try crypto.encrypt(data).write(to: blobURL(name), options: .atomic)
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
        guard let stored = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            items = try decoder.decode([ClipItem].self, from: crypto.decrypt(stored))
        } catch {
            EppLog.error("클립보드", "기록을 읽지 못함 \(error)")
            unreadableIndex = true
            return
        }
        if !EppCrypto.isEncrypted(stored) { encryptOldFiles() }
    }

    /// 암호화하기 전에 저장한 기록을 한 번 암호화해 둔다.
    private func encryptOldFiles() {
        for name in items.flatMap({ [$0.imageFile, $0.rtfFile] }).compactMap({ $0 }) {
            let url = blobURL(name)
            guard let data = try? Data(contentsOf: url), !EppCrypto.isEncrypted(data),
                  let sealed = try? crypto.encrypt(data) else { continue }
            try? sealed.write(to: url, options: .atomic)
        }
        saveNow()
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
        if unreadableIndex {
            unreadableIndex = false
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? FileManager.default.moveItem(at: indexURL,
                                              to: directory.appendingPathComponent("history-unreadable-\(stamp).json"))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            try crypto.encrypt(data).write(to: indexURL, options: .atomic)
        } catch {
            EppLog.error("클립보드", "기록 저장 실패 \(error)")
        }
    }
}
