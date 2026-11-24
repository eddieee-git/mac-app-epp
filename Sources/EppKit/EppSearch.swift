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

    /// 명령 이름과 맞는지: 입력이 이름의 일부(예: "캡" → "캡처")이거나, 입력에 이름이 들어 있으면(예: "새 스티커 쓰기").
    public func matchesCommand(_ names: String...) -> Bool {
        guard !text.isEmpty else { return false }
        return names.contains { name in
            name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || text.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// "5분", "1시간 30분", "90초", "10m", "1h 5m" 같은 시간. 단위가 하나도 없으면 nil.
    public var duration: Int? {
        let lower = text.lowercased()
        let units: [(pattern: String, seconds: Int)] = [
            (#"(\d+)\s*(시간|hours?|hrs?|h)\b"#, 3600), (#"(\d+)\s*(분|minutes?|mins?|m)\b"#, 60),
            (#"(\d+)\s*(초|seconds?|secs?|s)\b"#, 1),
        ]
        var total = 0, found = false
        for (pattern, seconds) in units {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            for match in regex.matches(in: lower, range: range) {
                if let r = Range(match.range(at: 1), in: lower), let value = Int(lower[r]) {
                    total += value * seconds
                    found = true
                }
            }
        }
        return found && total > 0 ? total : nil
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
