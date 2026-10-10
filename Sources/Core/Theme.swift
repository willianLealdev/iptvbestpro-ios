import SwiftUI

/// Marca do dono do aparelho (admin ou revenda) e tema escolhido no painel — igual aos apps Android, Roku e TV.
/// 1 OneUI · 2 Glossy · 3 Black Panther · 4 MovieUI · 5 VUI · 6 Natal · 7 Halloween · 8 BestPro (padrão)
struct Brand {
    var name = Config.appName
    var logo = Config.defaultLogo
    var showName = true
    var banner = ""
    var backgroundImage = ""
    var overlay: Double = 0.55
    var themeID = "8"
    var ms: JObj = [:]            // cores do modelo (personalizadas no painel ou as originais do modelo)
    var posters: [String] = []    // MovieUI: pôsteres do dono do aparelho

    init() {}
    init(_ tc: JObj) {
        name = tc.s("brand_name").isEmpty ? Config.appName : tc.s("brand_name")
        logo = tc.s("logo").isEmpty ? Config.defaultLogo : tc.s("logo")
        showName = tc.s("show_brand_name") != "0"
        banner = tc.s("banner")
        backgroundImage = tc.s("background_image")
        let o = Double(tc.s("background_overlay")) ?? 55
        overlay = max(0, min(95, o)) / 100
        themeID = tc.s("theme_id").isEmpty ? "8" : tc.s("theme_id")
        let custom = tc.s("customized") == "1"
        ms = custom && !tc.o("model_settings").isEmpty ? tc.o("model_settings") : tc.o("model_defaults")
    }

    func color(_ key: String, _ def: String) -> Color { Color(hex: ms.s(key)) ?? Color(hex: def)! }
    func colorOpt(_ keys: [String]) -> Color? {
        for k in keys { if let c = Color(hex: ms.s(k)) { return c } }
        return nil
    }
    func on(_ key: String) -> Bool { ms.s(key) != "0" }

    /// Cor de destaque (foco, botões principais)
    var accent: Color { colorOpt(["theme_primary", "accent", "accent_start", "buttons", "live_color"]) ?? Color(hex: "#F5B301")! }
    var accentIsLight: Bool {
        guard let hex = ["theme_primary", "accent", "accent_start", "buttons", "live_color"].map({ ms.s($0) }).first(where: { Color(hex: $0) != nil }),
              let rgb = Color.rgb(hex) else { return true }
        return (0.299 * rgb.0 + 0.587 * rgb.1 + 0.114 * rgb.2) > 0.6
    }
    var card: Color { colorOpt(["theme_surface", "card", "panel_top"]) ?? (ms.s("tile_auto") == "0" ? (Color(hex: ms.s("tile_color")) ?? Color(white: 0.12)) : Color(white: 0.12)) }
    var text: Color { Color(hex: ms.s("theme_text")) ?? .white }
    var bgTop: Color? { colorOpt(["bg_top", "bg", "theme_background"]) }
    var bgBottom: Color? { Color(hex: ms.s("bg_bottom")) ?? bgTop }

    static var saved: Brand {
        if let tc = Prefs.json("bp_brand") as? JObj { return Brand(tc) }
        return Brand()
    }
}

extension Color {
    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        var h = hex.trimmed
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }
    init?(hex: String) {
        guard let c = Color.rgb(hex) else { return nil }
        self = Color(red: c.0, green: c.1, blue: c.2)
    }
    /// k > 0 clareia, k < 0 escurece (cor em hexadecimal)
    static func mix(_ hex: String, _ k: Double) -> Color {
        guard let c = rgb(hex) else { return Color(white: 0.15) }
        func f(_ v: Double) -> Double { k >= 0 ? v + (1 - v) * k : v * (1 + k) }
        return Color(red: f(c.0), green: f(c.1), blue: f(c.2))
    }
}

/// Tamanhos que mudam entre iPhone, iPad e Apple TV
enum UIScale {
    static var tv: Bool { DeviceInfo.isTV }
    static var phone: Bool { DeviceInfo.isPhone }
    static func v(_ phone: CGFloat, _ pad: CGFloat, _ tv: CGFloat) -> CGFloat { UIScale.tv ? tv : (UIScale.phone ? phone : pad) }
    static var pad: CGFloat { v(14, 24, 60) }
    static var body: CGFloat { v(15, 17, 29) }
    static var title: CGFloat { v(22, 28, 48) }
    static var small: CGFloat { v(12, 14, 23) }
    static var poster: CGFloat { v(108, 150, 230) }
    static var rowH: CGFloat { v(48, 54, 86) }
}
