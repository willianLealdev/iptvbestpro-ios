import SwiftUI

/// Telas principais (o resto abre por navegação a partir da tela inicial)
enum Route: Equatable {
    case splash
    case activation(status: String, message: String)
    case noList
    case playlists
    case home
}

/// Estado do app: ativação, marca, listas do aparelho e a lista em uso.
/// Mesmas regras dos outros apps:
///  - a licença é conferida ao abrir, ao voltar para a tela inicial (no máximo 1x por minuto) e a cada 10 minutos;
///  - aparelho excluído, resetado ou vencido no painel volta para a ativação na hora;
///  - se o painel trocar o servidor (ou o usuário) da lista, o app entra de novo pelo novo — na tela inicial
///    troca na hora; assistindo, troca quando o cliente voltar para a tela inicial.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var route: Route = .splash
    @Published var brand = Brand.saved
    @Published var status: JObj = Prefs.json("bp_status") as? JObj ?? [:]
    @Published var playlists: [JObj] = []
    @Published var playlist: JObj?
    @Published var login: JObj?
    @Published var toast: String?
    @Published var lang: String = L10n.current
    @Published var homeVisible = false
    @Published var expiryNotice: Int?          // dias que faltam (mostra o aviso na tela inicial)
    @Published var homeToken = UUID()          // muda quando a tela inicial deve ser montada de novo (outra lista)

    private(set) var xtream: Xtream?
    private var brandFresh = false
    private var lastLicCheck = Date.distantPast
    private var pending: JObj?                 // lista nova (servidor/usuário trocado no painel)
    private var pendingGone = false            // a lista em uso saiu do aparelho
    private var timer: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    var isReseller: Bool { status.s("owner") == "reseller" }
    /// Compra pela Apple: só para cliente direto (sem revenda)
    var canPurchase: Bool { !isReseller }
    var playlistID: String { playlist?.s("id") ?? "" }
    var playlistName: String { (playlist?.s("playlist_name")).flatMap { $0.isEmpty ? nil : $0 } ?? playlist?.s("user_name") ?? "" }
    var serverTimeZone: TimeZone {
        TimeZone(identifier: login?.o("server_info").s("timezone") ?? "") ?? .current
    }

    func show(_ msg: String, seconds: Double = 3.5) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func setLanguage(_ l: String) {
        Prefs.lang = l
        lang = L10n.current
    }

    // MARK: - Abertura

    func boot() {
        route = .splash
        startTimer()
        Task {
            await fetchBrand()
            #if DEBUG
            // Só nos testes automáticos (simulador do GitHub): ativa com o código de teste e abre uma tela
            if let code = UserDefaults.standard.string(forKey: "bpTestCode"), !code.isEmpty, status.s("status") != "active" {
                _ = await link(code: code)
                return
            }
            #endif
            await checkStatus()
        }
    }

    #if DEBUG
    var debugScreen: String? { UserDefaults.standard.string(forKey: "bpScreen") }
    #endif

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
                await self?.licenseCheck(force: true)
            }
        }
    }

    /// Tema e logo do dono do aparelho (conferidos ao abrir o app e depois de ativar)
    func fetchBrand() async {
        guard let j = try? await API.panel("app_details") else { return }
        var tc: JObj?
        if let d = j as? JObj {
            tc = d["theme_config"] as? JObj
            if tc == nil, let det = d["details"] as? [JObj] { tc = det.first?["theme_config"] as? JObj }
        } else if let arr = j as? [JObj] {
            tc = arr.first?["theme_config"] as? JObj
        }
        guard let tc else { return }
        Prefs.setJSON("bp_brand", tc)
        var b = Brand(tc)
        // MovieUI: o fundo são os pôsteres do dono do aparelho, trocando a cada 20 s
        if b.themeID == "4" && b.backgroundImage.isEmpty, let arr = try? await API.panel("get_poster") as? [JObj] {
            b.posters = arr.map { $0.s("poster_image") }.filter { !$0.isEmpty }
        }
        brand = b
    }

    func checkStatus() async {
        do {
            let o = try await API.panelFirst("device_status")
            saveStatus(o)
            if o.s("status") == "active" { await loadPlaylists(chooser: false) }
            else { activation(o.s("status").isEmpty ? "unlinked" : o.s("status"), "") }
        } catch {
            // sem servidor: usa a última situação conhecida
            if status.s("status") == "active" { await loadPlaylists(chooser: false) }
            else { activation("unlinked", t(isNetwork(error) ? "no_net" : "server_err")) }
        }
    }

    func saveStatus(_ o: JObj) {
        status = o
        Prefs.setJSON("bp_status", o)
    }

    private func isNetwork(_ e: Error) -> Bool { if case APIError.network = e { return true }; return false }

    // MARK: - Ativação

    func activation(_ st: String, _ msg: String) {
        if st == "unlinked" { clearLocal() }
        route = .activation(status: st, message: msg)
    }

    func clearLocal() {
        Prefs.clearLocal()
        playlist = nil; login = nil; playlists = []; xtream = nil; brandFresh = false
    }

    /// Código da revenda (6 letras) ou da assinatura (8 números). Devolve a mensagem de erro (ou nil).
    func link(code raw: String) async -> String? {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        let valid = (code.count == 6 && code.allSatisfy { $0.isLetter && $0.isASCII }) || (code.count == 8 && code.allSatisfy { $0.isNumber })
        guard valid else { return t("act_invalid") }
        do {
            let o = try await API.panelFirst("device_link", ["code": code])
            if o.s("success") == "1" { clearLocal() }
            saveStatus(o)
            if o.s("status") == "active" { await loadPlaylists(chooser: false); return nil }
            if o.s("success") != "1" { return o.s("MSG").isEmpty ? t("act_invalid") : o.s("MSG") }
            activation(o.s("status").isEmpty ? "pending" : o.s("status"), "")
            return nil
        } catch {
            return t(isNetwork(error) ? "no_net" : "server_err")
        }
    }

    /// Compra pela Apple confirmada: o painel confere a transação e ativa o aparelho
    func applePurchased(jws: String) async -> String? {
        do {
            let o = try await API.panelFirst("apple_iap", ["signed_transaction": jws])
            saveStatus(o)
            if o.s("status") == "active" {
                show(o.s("MSG").isEmpty ? t("iap_ok") : o.s("MSG"), seconds: 5)
                brandFresh = false
                await loadPlaylists(chooser: false)
                return nil
            }
            return o.s("MSG").isEmpty ? t("iap_fail") : o.s("MSG")
        } catch {
            return t(isNetwork(error) ? "no_net" : "server_err")
        }
    }

    /// Resetar licença: o cliente trocou de revenda e quer digitar um código novo
    func resetLicense() async -> Bool {
        do {
            _ = try await API.panel("device_reset")
            clearLocal()
            show(t("lic_done"))
            activation("unlinked", "")
            return true
        } catch {
            show(t("no_net"))
            return false
        }
    }

    // MARK: - Listas do aparelho

    func loadPlaylists(chooser: Bool, fresh: Bool = false) async {
        if !chooser { route = .splash }
        // depois de ativar (ou trocar de dono) busca de novo a marca do dono do aparelho
        if !chooser && !brandFresh { brandFresh = true; await fetchBrand() }
        do {
            let j = try await API.panel("get_device_user", fresh ? ["fresh": "1"] : [:])
            playlists = (j as? [JObj] ?? []).filter { !$0.s("user_name").isEmpty }
        } catch {
            show(t(isNetwork(error) ? "no_net" : "server_err"))
            if playlists.isEmpty { route = .noList; return }
        }
        if playlists.isEmpty { clearLocal(); route = .noList; return }
        if chooser { if route != .home { route = .playlists }; return }
        let saved = Prefs.str("bp_pl")
        let pick = playlists.first { $0.s("id") == saved }
        if pick == nil && !saved.isEmpty { Prefs.clearCatalog() } // a lista salva não é mais deste aparelho
        await enter(pick ?? playlists[0])
    }

    /// Entra na lista: faz o login no servidor IPTV pelo DNS que o painel indicou
    func enter(_ pl: JObj, fromChooser: Bool = false) async {
        if playlist?.s("id") != pl.s("id") {
            if playlist != nil || fromChooser { Prefs.clearCatalog() }
            Catalog.clearMemory()
        }
        route = .splash
        var base = pl.s("dns_base").trimmed
        while base.hasSuffix("/") { base.removeLast() }
        if !base.isEmpty && !base.lowercased().hasPrefix("http") { base = "http://" + base }
        let probe = Xtream(apiBase: base, streamBase: base, user: pl.s("user_name"), pass: pl.s("user_password"))
        guard let j = try? await probe.call("") as? JObj, j.o("user_info").s("auth") == "1" else {
            show(t("list_err"), seconds: 5)
            playlist = nil; login = nil; xtream = nil
            if playlists.count > 1 { route = .playlists } else { route = .noList }
            return
        }
        let si = j.o("server_info")
        let proto = si.s("server_protocol").isEmpty ? "http" : si.s("server_protocol")
        let port = proto == "https" ? si.s("https_port") : si.s("port")
        var stream = base
        if !si.s("url").isEmpty {
            stream = proto + "://" + si.s("url")
            if !port.isEmpty && port != "80" && port != "443" { stream += ":" + port }
        }
        playlist = pl
        login = j
        xtream = Xtream(apiBase: base, streamBase: stream, user: pl.s("user_name"), pass: pl.s("user_password"))
        Prefs.set("bp_pl", pl.s("id"))
        pending = nil; pendingGone = false
        homeToken = UUID()
        route = .home
        checkExpiry()
    }

    func refreshAll() async {
        Catalog.clearDisk()
        show(t("loading"))
        await loadPlaylists(chooser: false, fresh: true)
    }

    // MARK: - Licença e servidor

    /// Chamado quando a tela inicial aparece (no máximo 1x por minuto) e a cada 10 minutos
    func licenseCheck(force: Bool) async {
        if case .activation = route { return }
        if !force && Date().timeIntervalSince(lastLicCheck) < 60 { return }
        lastLicCheck = Date()
        guard let o = try? await API.panelFirst("device_status") else { return }
        saveStatus(o)
        let st = o.s("status")
        if !st.isEmpty && st != "active" {
            NotificationCenter.default.post(name: .bpStopPlayback, object: nil)
            activation(st, "")
            return
        }
        await serverCheck()
    }

    /// O painel trocou o servidor ou o usuário da lista (migração, queda, "Usar este", DNS editado)?
    /// Usuário que caiu some da lista do painel enquanto houver outro funcionando: aí o app entra pelo outro.
    private func serverCheck() async {
        guard let pl = playlist, login != nil, let j = try? await API.panel("get_device_user") as? [JObj] else { return }
        let arr = j.filter { !$0.s("user_name").isEmpty }
        if arr.isEmpty { return }
        playlists = arr
        if let cur = arr.first(where: { $0.s("id") == pl.s("id") }) {
            if Self.normDNS(cur.s("dns_base")) != Self.normDNS(pl.s("dns_base")) || cur.s("user_name") != pl.s("user_name") || cur.s("user_password") != pl.s("user_password") {
                pending = cur
            } else { return }
        } else {
            pendingGone = true
        }
        if homeVisible { _ = applyPending() }
    }

    /// Aplica a troca pendente (ao voltar para a tela inicial). Devolve true se trocou.
    @discardableResult
    func applyPending() -> Bool {
        if pendingGone {
            pendingGone = false
            Task { await loadPlaylists(chooser: false) }
            return true
        }
        guard let np = pending else { return false }
        pending = nil
        playlist = nil
        Catalog.clearMemory()
        Task { await enter(np) }
        return true
    }

    static func normDNS(_ s: String) -> String {
        var u = s.lowercased().trimmed
        while u.hasSuffix("/") { u.removeLast() }
        if !u.isEmpty && !u.hasPrefix("http://") && !u.hasPrefix("https://") { u = "http://" + u }
        if u.hasPrefix("http://") && u.hasSuffix(":80") { u.removeLast(3) }
        if u.hasPrefix("https://") && u.hasSuffix(":443") { u.removeLast(4) }
        return u
    }

    func homeAppeared() {
        homeVisible = true
        if applyPending() { return }
        Task { await licenseCheck(force: false) }
    }

    // MARK: - Aviso de vencimento

    private func checkExpiry() {
        guard let d = Int(status.s("days_left")), d <= 5 else { return }
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        if Prefs.str("bp_exp_shown") == String(today) { return }
        Prefs.set("bp_exp_shown", String(today))
        expiryNotice = d
    }

    var supportWhatsApp: String {
        let d = status.s("support_whatsapp").filter { $0.isNumber }
        return d.count >= 10 ? d : ""
    }
}

extension Notification.Name {
    /// Licença caiu: para tudo o que está tocando
    static let bpStopPlayback = Notification.Name("bpStopPlayback")
}
