import Foundation
import Security

/// Preferências do aparelho (UserDefaults). Tudo da lista atual (favoritos, continuar, posições)
/// fica com o prefixo "pl_" e é apagado quando o cliente troca de lista ou o aparelho é resetado.
enum Prefs {
    static let ud = UserDefaults.standard

    static func str(_ k: String, _ d: String = "") -> String { ud.string(forKey: k) ?? d }
    static func set(_ k: String, _ v: String?) { if let v { ud.set(v, forKey: k) } else { ud.removeObject(forKey: k) } }
    /// Grava já no disco (ID do aparelho e situação da ativação não podem se perder se o app for fechado na hora)
    static func flush() { ud.synchronize() }
    static func int(_ k: String, _ d: Int = 0) -> Int { ud.object(forKey: k) == nil ? d : ud.integer(forKey: k) }
    static func setInt(_ k: String, _ v: Int) { ud.set(v, forKey: k) }
    static func bool(_ k: String, _ d: Bool) -> Bool { ud.object(forKey: k) == nil ? d : ud.bool(forKey: k) }
    static func setBool(_ k: String, _ v: Bool) { ud.set(v, forKey: k) }
    static func json(_ k: String) -> Any? { (ud.string(forKey: k)).flatMap { JSONUtil.object($0) } }
    static func setJSON(_ k: String, _ v: Any?) {
        guard let v else { ud.removeObject(forKey: k); return }
        let t = JSONUtil.string(v)
        if t.isEmpty { ud.removeObject(forKey: k) } else { ud.set(t, forKey: k) }
    }
    static func del(_ k: String) { ud.removeObject(forKey: k) }

    /// Apaga favoritos, continuar assistindo, posições e buscas (troca de lista)
    static func clearCatalog() {
        for k in ud.dictionaryRepresentation().keys where k.hasPrefix("pl_") { ud.removeObject(forKey: k) }
    }
    /// Aparelho desvinculado/resetado: apaga tudo, menos o idioma e as preferências do player
    static func clearLocal() {
        let keep: Set<String> = ["bp_did", "lang", "buffer_mode", "time_24h", "live_format", "autoplay_next", "cat_reverse", "card_title",
                                 "multi_layout", "auto_update_h", "subtitles", "adult_pin", "recent_limit"]
        for k in ud.dictionaryRepresentation().keys where k.hasPrefix("bp_") || k.hasPrefix("pl_") {
            if !keep.contains(k) { ud.removeObject(forKey: k) }
        }
        Catalog.clearDisk()
    }

    // Preferências do usuário (Configurações)
    static var lang: String { get { str("lang") } set { set("lang", newValue) } }
    static var bufferStable: Bool { get { bool("buffer_mode", true) } set { setBool("buffer_mode", newValue) } }
    static var time24h: Bool { get { bool("time_24h", true) } set { setBool("time_24h", newValue) } }
    /// 0 = automático (HLS .m3u8, e .ts se não tocar) · 1 = HLS · 2 = TS (MPEG-TS pelo player VLC)
    static var liveFormat: Int { get { int("live_format", 0) } set { setInt("live_format", newValue) } }
    static var autoplayNext: Bool { get { bool("autoplay_next", true) } set { setBool("autoplay_next", newValue) } }
    static var catReverse: Bool { get { bool("cat_reverse", false) } set { setBool("cat_reverse", newValue) } }
    static var cardTitle: Bool { get { bool("card_title", true) } set { setBool("card_title", newValue) } }
    static var subtitles: Bool { get { bool("subtitles", true) } set { setBool("subtitles", newValue) } }
    /// Multitela: 2 ou 4 telas (no iPhone no máximo 2)
    static var multiLayout: Int { get { int("multi_layout", 4) } set { setInt("multi_layout", newValue) } }
    /// Atualização automática da lista (horas que o catálogo fica guardado no aparelho)
    static var autoUpdateHours: Int { get { int("auto_update_h", 6) } set { setInt("auto_update_h", newValue) } }
    static var recentLimit: Int { get { int("recent_limit", 30) } set { setInt("recent_limit", newValue) } }
    static var adultPin: String { get { str("adult_pin") } set { set("adult_pin", newValue.isEmpty ? nil : newValue) } }
}

/// ID do aparelho: guardado no Keychain, continua o mesmo mesmo se o app for apagado e instalado de novo
/// (assim o cliente não perde a ativação ao reinstalar).
enum DeviceID {
    private static let service = "com.iptvbestpro.app.device"
    static let value: String = {
        if let v = read(), !v.isEmpty { return v }
        var v = "ios"
        let hex = Array("0123456789abcdef")
        for _ in 0..<14 { v.append(hex[Int.random(in: 0..<16)]) }
        save(v)
        return v
    }()

    private static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "id", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let v = String(data: d, encoding: .utf8), !v.isEmpty else {
            return UserDefaults.standard.string(forKey: "bp_did")
        }
        return v
    }
    private static func save(_ v: String) {
        UserDefaults.standard.set(v, forKey: "bp_did")
        UserDefaults.standard.synchronize()
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "id"]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(v.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
