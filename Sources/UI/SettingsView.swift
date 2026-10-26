import SwiftUI
import StoreKit

/// Configurações (as mesmas do app Android, menos o que a Apple não permite: baixar vídeos e atualizar fora da App Store)
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Choice?
    @State private var tick = 0
    @State private var askReset = false
    @State private var pinSheet = false
    @State private var showSupport = false
    @State private var showDevice = false
    @State private var showSubscription = false
    @State private var cacheSize = ""
    @State private var iapError = ""
    @ObservedObject private var iap = Purchases.shared

    struct Choice: Identifiable {
        let id = UUID()
        let title: String
        let options: [(String, () -> Void)]
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("settings"), onBack: { dismiss() })
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: UIScale.v(300, 320, 520)), spacing: UIScale.v(10, 14, 30))], spacing: UIScale.v(10, 14, 30)) {
                    row("globe", t("language"), langName(Prefs.lang)) {
                        choice = Choice(title: t("language"), options: [("", "lang_auto"), ("pt", "Português"), ("en", "English"), ("es", "Español")].map { l -> (String, () -> Void) in
                            (l.0.isEmpty ? t(l.1) : l.1, { app.setLanguage(l.0) })
                        })
                    }
                    NavigationLink(value: SettingsDest.profile) { rowLabel("person.crop.circle", t("profile"), app.playlistName) }.buttonStyle(TileStyle())
                    row("person.text.rectangle", t("device"), DeviceID.value) { showDevice = true }
                    row("message.fill", t("support"), app.status.s("support_name")) { showSupport = true }
                    row("arrow.clockwise", t("refresh"), "") { Task { await app.refreshAll() } }
                    NavigationLink(value: Dest.playlists) { rowLabel("list.bullet", t("playlist"), app.playlistName) }.buttonStyle(TileStyle())
                    row("speedometer", t("buf_title"), t(Prefs.bufferStable ? "buf_stable" : "buf_fast")) {
                        choice = Choice(title: t("buf_title"), options: [(t("buf_stable") + " — " + t("buf_stable_desc"), { Prefs.bufferStable = true; tick += 1 }),
                                                                          (t("buf_fast") + " — " + t("buf_fast_desc"), { Prefs.bufferStable = false; tick += 1 })])
                    }
                    row("antenna.radiowaves.left.and.right", t("stream_format"), [t("fmt_auto"), "HLS (.m3u8)", "MPEG-TS (.ts)"][min(2, Prefs.liveFormat)]) {
                        choice = Choice(title: t("stream_format"), options: [(t("fmt_auto"), { Prefs.liveFormat = 0; tick += 1 }), ("HLS (.m3u8)", { Prefs.liveFormat = 1; tick += 1 }),
                                                                              ("MPEG-TS (.ts)", { Prefs.liveFormat = 2; tick += 1 })])
                    }
                    row("clock", t("time_format"), Prefs.time24h ? "24h" : "12h") {
                        choice = Choice(title: t("time_format"), options: [("24h (18:30)", { Prefs.time24h = true; tick += 1 }), ("12h (6:30 PM)", { Prefs.time24h = false; tick += 1 })])
                    }
                    row("arrow.triangle.2.circlepath", t("automation"), t("every_h", "\(Prefs.autoUpdateHours)")) {
                        choice = Choice(title: t("automation"), options: [1, 3, 6, 12, 24].map { h -> (String, () -> Void) in (t("every_h", "\(h)"), { Prefs.autoUpdateHours = h; tick += 1 }) })
                    }
                    row("square.grid.2x2", t("multi"), t("screens_n", "\(effectiveMulti)")) {
                        let opts = DeviceInfo.isPhone ? [2] : [2, 4]
                        choice = Choice(title: t("multi"), options: opts.map { n -> (String, () -> Void) in (t("screens_n", "\(n)"), { Prefs.multiLayout = n; tick += 1 }) } + [(t("multi_open"), { player.multiscreen = true })])
                    }
                    toggle("forward.end", t("autoplay_next"), Prefs.autoplayNext) { Prefs.autoplayNext = $0 }
                    toggle("arrow.up.arrow.down", t("cat_reverse"), Prefs.catReverse) { Prefs.catReverse = $0; Catalog.clearMemory() }
                    toggle("textformat", t("card_title"), Prefs.cardTitle) { Prefs.cardTitle = $0 }
                    toggle("captions.bubble", t("subtitles_on"), Prefs.subtitles) { Prefs.subtitles = $0 }
                    row("clock.arrow.circlepath", t("recent_limit"), "\(Prefs.recentLimit)") {
                        choice = Choice(title: t("recent_limit"), options: [10, 20, 30, 50].map { n -> (String, () -> Void) in ("\(n)", { Prefs.recentLimit = n; tick += 1 }) })
                    }
                    row("lock.fill", t("adults_content"), t(Prefs.adultPin.isEmpty ? "pin_off" : "pin_on")) { pinSheet = true }
                    NavigationLink(value: SettingsDest.speed) { rowLabel("gauge.with.dots.needle.67percent", t("speed_test"), "") }.buttonStyle(TileStyle())
                    NavigationLink(value: SettingsDest.feedback) { rowLabel("envelope", t("feedback"), "") }.buttonStyle(TileStyle())
                    row("trash", t("clear_cache"), cacheSize) {
                        Catalog.clearDisk()
                        cacheSize = Fmt.bytes(Catalog.diskSize())
                        app.show(t("cache_cleared"))
                    }
                    if app.canPurchase {
                        row("creditcard", t("iap_title"), iap.price) { showSubscription = true }
                    }
                    #if os(iOS)
                    if let u = URL(string: Config.privacyURL) {
                        Link(destination: u) { rowLabel("hand.raised", t("privacy"), "") }.buttonStyle(TileStyle())
                    }
                    #endif
                    NavigationLink(value: SettingsDest.about) { rowLabel("info.circle", t("about"), "v" + Config.version) }.buttonStyle(TileStyle())
                    row("arrow.counterclockwise", t("lic_reset"), "") { askReset = true }
                }
                .padding(UIScale.pad)
                .id(tick)
            }
        }
        .onAppear { cacheSize = Fmt.bytes(Catalog.diskSize()) }
        .navigationDestination(for: SettingsDest.self) { d in
            switch d {
            case .profile: ProfileView().screen()
            case .speed: SpeedTestView().screen()
            case .feedback: FeedbackView().screen()
            case .about: AboutView().screen()
            }
        }
        .confirmationDialog(choice?.title ?? "", isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } }), titleVisibility: .visible) {
            if let c = choice {
                ForEach(Array(c.options.enumerated()), id: \.offset) { _, o in Button(o.0) { o.1() } }
                Button(t("cancel"), role: .cancel) {}
            }
        }
        .alert(t("lic_reset"), isPresented: $askReset) {
            Button(t("lic_cancel"), role: .cancel) {}
            Button(t("lic_yes"), role: .destructive) { Task { _ = await app.resetLicense() } }
        } message: { Text(t("lic_reset_msg")) }
        .alert(t("device"), isPresented: $showDevice) { Button(t("close"), role: .cancel) {} } message: { Text(DeviceID.value) }
        .sheet(isPresented: $pinSheet) { AdultPinSheet(onDone: { tick += 1 }) }
        .sheet(isPresented: $showSupport) { SupportSheet() }
        .sheet(isPresented: $showSubscription) { SubscriptionSheet().environmentObject(app) }
    }

    private var effectiveMulti: Int { DeviceInfo.isPhone ? 2 : (Prefs.multiLayout == 2 ? 2 : 4) }

    private func langName(_ l: String) -> String {
        ["pt": "Português", "en": "English", "es": "Español"][l] ?? t("lang_auto")
    }

    private func manageSubscriptions() {
        #if os(iOS)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            Task { try? await AppStore.showManageSubscriptions(in: scene) }
        }
        #else
        app.show(t("iap_manage_tv"), seconds: 6)
        #endif
    }

    private func row(_ icon: String, _ title: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, title, sub) }.buttonStyle(TileStyle())
    }

    private func rowLabel(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: UIScale.v(12, 14, 26)) {
            Image(systemName: icon).font(.system(size: UIScale.v(20, 22, 38))).foregroundColor(app.brand.accent).frame(width: UIScale.v(30, 34, 60))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: UIScale.body, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.6)).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(UIScale.v(14, 16, 28))
        .frame(maxWidth: .infinity, minHeight: UIScale.v(64, 72, 120))
        .cardBG(app.brand.card.opacity(0.85))
    }

    private func toggle(_ icon: String, _ title: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Button { set(!on); tick += 1 } label: {
            HStack(spacing: UIScale.v(12, 14, 26)) {
                Image(systemName: icon).font(.system(size: UIScale.v(20, 22, 38))).foregroundColor(app.brand.accent).frame(width: UIScale.v(30, 34, 60))
                Text(title).font(.system(size: UIScale.body, weight: .semibold)).foregroundColor(.white).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: UIScale.v(22, 24, 40))).foregroundColor(on ? app.brand.accent : .white.opacity(0.4))
            }
            .padding(UIScale.v(14, 16, 28))
            .frame(maxWidth: .infinity, minHeight: UIScale.v(64, 72, 120))
            .cardBG(app.brand.card.opacity(0.85))
        }
        .buttonStyle(TileStyle())
    }
}

enum SettingsDest: Hashable { case profile, speed, feedback, about }

/// Conta: dados da lista no servidor IPTV e da ativação no painel
struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let u = app.login?.o("user_info") ?? [:]
        VStack(spacing: 0) {
            TopBar(title: t("profile"), onBack: { dismiss() })
            ScrollView {
                VStack(spacing: 10) {
                    info(t("playlist"), app.playlistName)
                    info(t("username"), u.s("username"))
                    info(t("acc_status"), u.s("status"))
                    if u.d("exp_date") > 0 { info(t("acc_expires"), Fmt.date(Date(timeIntervalSince1970: u.d("exp_date")))) }
                    if u.s("is_trial") == "1" { info(t("acc_trial"), t("yes")) }
                    info(t("acc_connections"), "\(u.s("active_cons").isEmpty ? "0" : u.s("active_cons")) / \(u.s("max_connections"))")
                    if u.d("created_at") > 0 { info(t("acc_created"), Fmt.date(Date(timeIntervalSince1970: u.d("created_at")))) }
                    Divider().background(Color.white.opacity(0.2)).padding(.vertical, 6)
                    info(t("lic_until"), app.status.s("expires_at").isEmpty ? "—" : app.status.s("expires_at"))
                    if !app.status.s("days_left").isEmpty { info(t("lic_days"), app.status.s("days_left")) }
                    if !app.status.s("reseller").isEmpty { info(t("reseller"), app.status.s("reseller")) }
                    info(t("device"), DeviceID.value)
                    info(t("app_version"), "v\(Config.version) (\(Config.build)) · \(DeviceInfo.platformName)")
                }
                .padding(UIScale.pad)
                .frame(maxWidth: UIScale.v(.infinity, 760, 1200))
            }
        }
    }
    private func info(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(v.isEmpty ? "—" : v).font(.system(size: UIScale.body, weight: .semibold)).foregroundColor(.white).multilineTextAlignment(.trailing)
        }
        .padding(UIScale.v(12, 14, 24)).cardBG(Color.white.opacity(0.06))
        #if os(tvOS)
        .focusable(true)
        #endif
    }
}

/// Velocidade da internet (download e tempo de resposta)
struct SpeedTestView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mbps: Double?
    @State private var ping: Int?
    @State private var running = false
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("speed_test"), onBack: { dismiss() })
            Spacer()
            VStack(spacing: UIScale.v(16, 20, 40)) {
                Text(mbps.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: UIScale.v(64, 80, 150), weight: .heavy)).foregroundColor(app.brand.accent)
                Text("Mbps").font(.system(size: UIScale.title)).foregroundColor(.white.opacity(0.8))
                if let ping { Text(t("ping") + ": \(ping) ms").font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.8)) }
                if running { ProgressView(value: progress).tint(app.brand.accent).frame(maxWidth: 400) }
                if let m = mbps { Text(t(m >= 25 ? "speed_good" : (m >= 10 ? "speed_ok" : "speed_bad"))).font(.system(size: UIScale.body)).foregroundColor(.white).multilineTextAlignment(.center) }
                Button(running ? t("testing") : t("speed_start")) { Task { await run() } }.buttonStyle(PillStyle(primary: true)).disabled(running)
            }
            .padding()
            Spacer()
        }
    }

    private func run() async {
        running = true; progress = 0; mbps = nil; ping = nil
        defer { running = false }
        // tempo de resposta do painel
        if let u = URL(string: Config.server + "/.well-known/security.txt") {
            let t0 = Date()
            _ = try? await URLSession.shared.data(from: u)
            ping = Int(Date().timeIntervalSince(t0) * 1000)
        }
        // baixa pedaços de 5 MB por até 12 segundos e calcula a média
        let t0 = Date()
        var got: Int64 = 0
        for i in 0..<8 {
            guard let u = URL(string: "https://speed.cloudflare.com/__down?bytes=5000000&r=\(i)") else { break }
            guard let (d, _) = try? await URLSession.shared.data(from: u) else { break }
            got += Int64(d.count)
            let s = Date().timeIntervalSince(t0)
            mbps = Double(got) * 8 / max(0.1, s) / 1_000_000
            progress = Double(i + 1) / 8
            if s > 12 { break }
        }
        progress = 1
    }
}

/// Enviar mensagem para a revenda / suporte (aparece em Relatórios no painel)
struct FeedbackView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("feedback"), onBack: { dismiss() })
            ScrollView {
                VStack(spacing: 14) {
                    TextField(t("fb_title"), text: $title).font(.system(size: UIScale.body)).padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    TextField(t("fb_msg"), text: $message, axis: .vertical).lineLimit(4...10).font(.system(size: UIScale.body)).padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    Button { send() } label: { HStack { if sending { ProgressView() }; Text(t("send")) } }.buttonStyle(PillStyle(primary: true)).disabled(sending)
                }
                .padding(UIScale.pad)
                .frame(maxWidth: UIScale.v(.infinity, 700, 1200))
            }
        }
    }

    private func send() {
        guard !title.trimmed.isEmpty, !message.trimmed.isEmpty else { app.show(t("fb_fill")); return }
        sending = true
        Task {
            let u = app.login?.o("user_info").s("username") ?? ""
            let ok = (try? await API.panel("post_report", ["user_name": u, "user_pass": "", "report_title": title, "report_msg": message])) != nil
            sending = false
            app.show(t(ok ? "fb_sent" : "server_err"))
            if ok { dismiss() }
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("about"), onBack: { dismiss() })
            ScrollView {
                CardBox {
                    RemoteImage(url: app.brand.logo, fill: false, placeholder: "").frame(width: UIScale.v(100, 130, 220), height: UIScale.v(100, 130, 220))
                    Text(app.brand.name).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white)
                    Text("v\(Config.version) (\(Config.build)) · \(DeviceInfo.platformName)").foregroundColor(.white.opacity(0.75)).font(.system(size: UIScale.body))
                    Text(t("about_text")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center)
                    DeviceIDBox()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }
}

/// Senha do conteúdo adulto: criar, trocar ou tirar
struct AdultPinSheet: View {
    var onDone: () -> Void
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var old = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var err = ""

    var body: some View {
        ZStack {
            BrandBackground()
            ScrollView {
                CardBox {
                    Text(t("adults_content")).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white)
                    Text(t("adult_info")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.75)).multilineTextAlignment(.center)
                    if !Prefs.adultPin.isEmpty { field(t("pin_old"), $old) }
                    field(t("pin_new"), $new1)
                    field(t("pin_confirm"), $new2)
                    if !err.isEmpty { Text(err).foregroundColor(.orange).font(.system(size: UIScale.small)) }
                    Button(t("save")) { save() }.buttonStyle(PillStyle(primary: true))
                    if !Prefs.adultPin.isEmpty {
                        Button(t("pin_remove")) {
                            guard old == Prefs.adultPin else { err = t("pin_wrong"); return }
                            Prefs.adultPin = ""; AdultLock.shared.unlocked = false; Catalog.clearMemory(); onDone(); dismiss()
                        }.buttonStyle(PillStyle())
                    }
                    Button(t("cancel")) { dismiss() }.buttonStyle(PillStyle())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }
    private func field(_ ph: String, _ b: Binding<String>) -> some View {
        SecureField(ph, text: b).font(.system(size: UIScale.body)).padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
            .frame(maxWidth: 420)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }
    private func save() {
        if !Prefs.adultPin.isEmpty && old != Prefs.adultPin { err = t("pin_wrong"); return }
        guard new1.count >= 4 else { err = t("pin_short"); return }
        guard new1 == new2 else { err = t("pin_mismatch"); return }
        Prefs.adultPin = new1
        AdultLock.shared.unlocked = false
        Catalog.clearMemory()
        onDone()
        dismiss()
    }
}
