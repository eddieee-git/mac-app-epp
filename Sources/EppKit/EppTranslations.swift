import Foundation

/// 화면 문구 번역 사전. 한국어 문구를 열쇠로 쓰고, Epp 언어가 영어면 짝지은 영어로 바꾼다(없으면 한국어 그대로).
/// 본체와 기능마다 사전(`pairs`)은 따로 두고, 찾는 방법은 이것 하나를 같이 쓴다.
/// 같은 열쇠가 두 번 들어가도 죽지 않고 앞의 것을 쓴다. 자체 점검이 `duplicateKeys`로 알려 준다.
/// 빠진 번역은 scripts/test.sh가 찾는다(사전 줄은 `("한국어", "English"),` 꼴).
public struct EppTranslations: Sendable {
    public let english: [String: String]
    public let duplicateKeys: [String]

    public init(_ pairs: [(String, String)]) {
        english = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>(), dupes: [String] = []
        for (key, _) in pairs where !seen.insert(key).inserted { dupes.append(key) }
        duplicateKeys = dupes
    }

    /// 지금 언어의 문구. args가 있으면 `%@`, `%ld` 등을 채운다.
    public func text(_ korean: String, _ args: [CVarArg] = []) -> String {
        let format = EppLanguage.isKorean ? korean : (english[korean] ?? korean)
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
}
