import Foundation

/// Epp 빠른 검색에서 찾는 말. 띄어 쓴 낱말이 모두 들어 있으면 맞는다(대소문자·악센트 무시).
public struct EppSearchQuery: Sendable {
    public let text: String
    public let words: [String]

    public init(_ text: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        words = self.text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var isEmpty: Bool { words.isEmpty }

    /// 여러 글 중 어디에든 낱말이 모두 들어 있는지(낱말마다 다른 글에 있어도 된다).
    public func matches(_ texts: String?...) -> Bool {
        let present = texts.compactMap { $0 }
        guard !words.isEmpty, !present.isEmpty else { return false }
        return words.allSatisfy { word in
            present.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// 첫 낱말이 나온 곳 앞뒤를 한 줄로 잘라 보여 줄 글.
    public func snippet(_ text: String?, length: Int = 80) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        guard let word = words.first,
              let range = flat.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flat.prefix(length))
        }
        let start = flat.index(range.lowerBound, offsetBy: -20, limitedBy: flat.startIndex) ?? flat.startIndex
        let piece = String(flat[start...].prefix(length))
        return (start > flat.startIndex ? "…" : "") + piece
    }
}

/// 빠른 검색 결과 한 줄. 누르면(↩) `open`을 부른다.
public struct EppSearchResult: Identifiable {
    public let id: String
    public let title: String
    public let detail: String?
    /// SF Symbol 이름
    public let symbol: String
    public let date: Date?
    public let open: @MainActor () -> Void

    public init(id: String, title: String, detail: String? = nil, symbol: String, date: Date? = nil,
                open: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.date = date
        self.open = open
    }
}

/// 기능끼리 주고받는 부탁. 보낸 기능은 받을 기능이 켜져 있는지 몰라도 된다(`context.send`가 false면 아무도 못 받음).
public enum EppRequest: Sendable {
    /// 이 글로 새 스티커를 만든다(스티커 기능).
    case makeSticky(text: String)
}
