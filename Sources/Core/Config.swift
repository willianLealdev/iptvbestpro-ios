import Foundation

/// IPTV Best Pro — app de iPhone, iPad e Apple TV.
/// Mesmo painel dos apps Android, Roku e TV: ativação por código, listas do aparelho, TV ao vivo, filmes e séries.
enum Config {
    static let server = "https://iptvbestpro.com"
    static let appID = "com.iptvbestpro.app"
    static let appName = "IPTV Best Pro"
    /// Assinatura anual pela Apple (só para cliente direto; aparelho de revenda nunca vê a compra)
    static let productYear = "com.iptvbestpro.app.year"
    /// Notificações (mesmo App ID do OneSignal do app Android)
    static let oneSignalID = "8dc84058-f598-4572-8d2e-4089491f9ae7"
    /// Os servidores IPTV respondem melhor a players conhecidos (o mesmo usado no app Roku)
    static let userAgent = "IPTVSmartersPlayer"
    static let defaultLogo = server + "/assets/images/brand/iptvbestpro_logo.png"
    static let defaultBackground = server + "/tv/bg.jpg"
    static let privacyURL = server + "/privacy_policy"

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }

    /// Categorias adultas (ficam escondidas; só aparecem com a senha de conteúdo adulto)
    static let adultPattern = try! NSRegularExpression(pattern: "adult|adulto|xxx|\\+18|18\\+|porn|hot\\b", options: [.caseInsensitive])
    static func isAdult(_ name: String) -> Bool {
        adultPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}
