import Foundation

/// Os servidores IPTV mandam o mesmo campo às vezes como texto, às vezes como número.
/// Por isso os dados ficam como dicionário e são lidos com estes atalhos tolerantes.
typealias JObj = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func s(_ key: String) -> String {
        guard let v = self[key] else { return "" }
        if let x = v as? String { return x }
        if let n = v as? NSNumber { return n.stringValue }
        if v is NSNull { return "" }
        return "\(v)"
    }
    func i(_ key: String) -> Int {
        let t = s(key).trimmingCharacters(in: .whitespaces)
        if let n = Int(t) { return n }
        if let d = Double(t) { return Int(d) }
        return 0
    }
    func d(_ key: String) -> Double { Double(s(key)) ?? 0 }
    func o(_ key: String) -> JObj { self[key] as? JObj ?? [:] }
    func a(_ key: String) -> [JObj] { self[key] as? [JObj] ?? [] }
    func has(_ key: String) -> Bool { !s(key).isEmpty }
}

/// Item de lista (canal, filme, série, episódio) que pode ir para a navegação do SwiftUI
struct Item: Identifiable, Hashable {
    let id: String
    let raw: JObj

    init(_ raw: JObj, id: String? = nil) {
        self.raw = raw
        self.id = id ?? (raw.s("stream_id").isEmpty ? (raw.s("series_id").isEmpty ? raw.s("id") : raw.s("series_id")) : raw.s("stream_id"))
    }
    static func == (l: Item, r: Item) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var name: String { raw.s("name").isEmpty ? raw.s("title") : raw.s("name") }
    var image: String {
        for k in ["stream_icon", "cover", "img", "movie_image", "cover_big"] where !raw.s(k).isEmpty { return raw.s(k) }
        return ""
    }
    subscript(_ key: String) -> String { raw.s(key) }
}

enum JSONUtil {
    static func parse(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
    static func string(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj), let d = try? JSONSerialization.data(withJSONObject: obj) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
    static func object(_ text: String) -> Any? {
        guard let d = text.data(using: .utf8) else { return nil }
        return parse(d)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Textos do guia (EPG) vêm em base64
    var base64Decoded: String {
        guard let d = Data(base64Encoded: self, options: [.ignoreUnknownCharacters]), let t = String(data: d, encoding: .utf8) else { return self }
        return t
    }
    var urlPath: String { addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#&="))) ?? self }
}
