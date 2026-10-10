import SwiftUI

/// Categorias especiais no topo das listas
enum SpecialCat {
    static let search = "_search", fav = "_fav", recent = "_recent", cw = "_cw"
}

/// Senha do conteúdo adulto (Configurações): categorias adultas só aparecem com a senha
@MainActor
final class AdultLock: ObservableObject {
    static let shared = AdultLock()
    @Published var unlocked = false
    var enabled: Bool { !Prefs.adultPin.isEmpty }
    func check(_ pin: String) -> Bool { if pin == Prefs.adultPin { unlocked = true }; return unlocked }
}

@MainActor func filterCategories(_ cats: [JObj]) -> [JObj] {
    var l = cats.filter { !Config.isAdult($0.s("category_name")) || AdultLock.shared.enabled }
    if Prefs.catReverse { l.reverse() }
    return l
}

/// TV ao vivo: categorias, canais, prévia (iPad e Apple TV) e guia agora/a seguir
struct LiveView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = PlayerModel()
    @ObservedObject private var lock = AdultLock.shared

    @State private var cats: [JObj] = []
    @State private var catID = ""
    @State private var catName = ""
    @State private var chans: [JObj] = []
    @State private var loadingCats = true
    @State private var loadingChans = false
    @State private var showChans = false       // telas estreitas: categorias → canais
    @State private var playingID = ""
    @State private var epg: [JObj] = []
    @State private var askPin: JObj?
    @State private var pin = ""
    @State private var filter = ""
    @State private var catchup: Item?

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > 760
            VStack(spacing: 0) {
                TopBar(title: showChans && !wide ? catName : t("live"), onBack: back)
                if wide {
                    HStack(alignment: .top, spacing: UIScale.v(10, 14, 30)) {
                        categoryList.frame(width: g.size.width * 0.27)
                        channelList.frame(width: g.size.width * 0.33)
                        previewPane.frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, UIScale.pad).padding(.top, 8)
                } else {
                    Group { if showChans { channelList } else { categoryList } }
                        .padding(.horizontal, UIScale.pad).padding(.top, 8)
                }
            }
            .onAppear { if wide { resumePreview() } }
        }
        .task { await loadCats() }
        .onDisappear { preview.stop() }
        .onChange(of: player.request == nil) { closed in
            // voltou do canal em tela cheia: a prévia continua no mesmo canal
            if closed, let c = chans.first(where: { $0.s("stream_id") == playingID }), let x = app.xtream, !DeviceInfo.isPhone { preview.playLive(x, id: c.s("stream_id")) }
        }
        .alert(t("adult_pin"), isPresented: Binding(get: { askPin != nil }, set: { if !$0 { askPin = nil } })) {
            SecureField(t("adult_pin"), text: $pin)
            Button(t("cancel"), role: .cancel) { pin = "" }
            Button(t("ok")) {
                if lock.check(pin), let c = askPin { Task { await openCat(c) } } else { app.show(t("pin_wrong")) }
                pin = ""
            }
        }
        .navigationDestination(isPresented: Binding(get: { catchup != nil }, set: { if !$0 { catchup = nil } })) {
            if let c = catchup { CatchupView(channel: c).screen() }
        }
        #if os(tvOS)
        .onExitCommand { back() }
        #endif
    }

    private func back() {
        if showChans { showChans = false; return }
        preview.stop()
        dismiss()
    }

    // MARK: listas

    private var categoryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: UIScale.v(6, 8, 14)) {
                    NavigationLink(value: Dest.search) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: UIScale.body * 0.9))
                            Text(t("search_go")).font(.system(size: UIScale.body, weight: .medium))
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(RowStyle())
                    if !Library.favList("live").isEmpty {
                        catRow(["category_id": SpecialCat.fav, "category_name": t("favorites") + " (\(Library.favList("live").count))"], icon: "star.fill")
                    }
                    if !Library.cwList("live").isEmpty {
                        catRow(["category_id": SpecialCat.recent, "category_name": t("recent")], icon: "clock")
                    }
                    if loadingCats { Spinner().padding() }
                    ForEach(Array(cats.enumerated()), id: \.offset) { _, c in
                        catRow(c, icon: Config.isAdult(c.s("category_name")) && !lock.unlocked ? "lock.fill" : nil).id(c.s("category_id"))
                    }
                    if !loadingCats && cats.isEmpty { EmptyText(text: t("empty")) }
                }
                .padding(.vertical, 6)
            }
            .onAppear { if !catID.isEmpty { proxy.scrollTo(catID, anchor: .center) } }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func catRow(_ c: JObj, icon: String?) -> some View {
        Button { Task { await tapCat(c) } } label: {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: UIScale.body * 0.9)) }
                Text(c.s("category_name")).font(.system(size: UIScale.body, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(RowStyle(selected: catID == c.s("category_id")))
    }

    private var channelList: some View {
        VStack(spacing: 8) {
            if chans.count > 30 {
                TextField(t("filter_ph"), text: $filter)
                    .font(.system(size: UIScale.body)).padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    .disableAutocorrection(true)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: UIScale.v(6, 8, 14)) {
                        if loadingChans { Spinner().padding() }
                        ForEach(Array(visibleChans.enumerated()), id: \.offset) { i, c in
                            chanRow(c, number: (chans.firstIndex { $0.s("stream_id") == c.s("stream_id") } ?? i) + 1).id(c.s("stream_id"))
                        }
                        if !loadingChans && chans.isEmpty { EmptyText(text: t(catID == SpecialCat.fav ? "fav_empty" : "empty")) }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: playingID) { id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var visibleChans: [JObj] {
        let f = filter.trimmed.lowercased()
        return f.isEmpty ? chans : chans.filter { $0.s("name").lowercased().contains(f) }
    }

    private func chanRow(_ c: JObj, number: Int) -> some View {
        let fav = Library.isFav("live", c)
        return Button { tapChannel(c) } label: {
            HStack(spacing: UIScale.v(10, 12, 20)) {
                Text("\(number)").font(.system(size: UIScale.small, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(minWidth: UIScale.v(26, 30, 56))
                RemoteImage(url: c.s("stream_icon"), fill: false, placeholder: "tv").frame(width: UIScale.v(34, 40, 70), height: UIScale.v(26, 30, 50))
                Text((fav ? "★ " : "") + c.s("name")).font(.system(size: UIScale.body, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if c.s("tv_archive") == "1" { Image(systemName: "clock.arrow.circlepath").font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.6)) }
            }
        }
        .buttonStyle(RowStyle(selected: playingID == c.s("stream_id")))
        .contextMenu {
            Button { Library.toggleFav("live", c) ; app.show(t(Library.isFav("live", c) ? "fav_added" : "fav_removed")); chans = chans } label: {
                Label(t(fav ? "fav_del" : "fav_add"), systemImage: "star")
            }
            if c.s("tv_archive") == "1" {
                Button { catchup = Item(c) } label: { Label(t("catchup"), systemImage: "clock.arrow.circlepath") }
            }
        }
    }

    // MARK: prévia e guia

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: UIScale.v(10, 12, 22)) {
            ZStack {
                Color.black
                if playingID.isEmpty {
                    Image(systemName: "tv").font(.system(size: 50)).foregroundColor(.white.opacity(0.2))
                } else {
                    VideoSurface(model: preview)
                    if preview.state == .loading || preview.message != nil {
                        VStack(spacing: 8) {
                            if preview.state == .loading { Spinner() }
                            if let m = preview.message { Text(m).font(.system(size: UIScale.small)).foregroundColor(.white) }
                        }
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))

            if let c = chans.first(where: { $0.s("stream_id") == playingID }) {
                Text(c.s("name")).font(.system(size: UIScale.body * 1.1, weight: .bold)).foregroundColor(app.brand.accent).lineLimit(1)
                EPGNowNext(listings: epg)
                HStack(spacing: 10) {
                    Button { openFull(c) } label: { Label(t("fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right") }.buttonStyle(PillStyle(primary: true))
                    Button { Library.toggleFav("live", c); app.show(t(Library.isFav("live", c) ? "fav_added" : "fav_removed")); chans = chans } label: {
                        Image(systemName: Library.isFav("live", c) ? "star.fill" : "star")
                    }.buttonStyle(PillStyle())
                    if c.s("tv_archive") == "1" {
                        Button { catchup = Item(c) } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(PillStyle())
                    }
                }
            } else {
                Text(t("pick_channel")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: ações

    private func loadCats() async {
        guard let x = app.xtream else { return }
        loadingCats = true
        let l = (try? await x.list("get_live_categories", playlistID: app.playlistID)) ?? []
        cats = filterCategories(l)
        loadingCats = false
        // abre a categoria do último canal assistido
        if catID.isEmpty, let last = Library.lastLive {
            if last.s("cat") == SpecialCat.fav || last.s("cat") == SpecialCat.recent {
                await openCat(["category_id": last.s("cat"), "category_name": t(last.s("cat") == SpecialCat.fav ? "favorites" : "recent")], select: last.s("sid"))
            } else if let c = cats.first(where: { $0.s("category_id") == last.s("cat") }) {
                await openCat(c, select: last.s("sid"))
            }
            if DeviceInfo.isPhone { showChans = false }
        }
        // tela larga (iPad, Apple TV): já mostra os canais da primeira categoria
        if catID.isEmpty && !DeviceInfo.isPhone, let first = cats.first(where: { !Config.isAdult($0.s("category_name")) }) {
            await openCat(first)
        }
        #if DEBUG
        // teste automático: abre o primeiro canal em tela cheia
        if app.debugScreen == "play", let c = chans.first { openFull(c) }
        #endif
    }

    private func tapCat(_ c: JObj) async {
        if Config.isAdult(c.s("category_name")) && !lock.unlocked { askPin = c; return }
        await openCat(c)
    }

    private func openCat(_ c: JObj, select: String? = nil) async {
        catID = c.s("category_id"); catName = c.s("category_name"); filter = ""
        showChans = true
        switch catID {
        case SpecialCat.fav: chans = Library.favList("live")
        case SpecialCat.recent: chans = Library.cwList("live")
        default:
            guard let x = app.xtream else { return }
            loadingChans = true; chans = []
            chans = (try? await x.list("get_live_streams", ["category_id": catID], playlistID: app.playlistID)) ?? []
            loadingChans = false
        }
        if let select, let c = chans.first(where: { $0.s("stream_id") == select }), !DeviceInfo.isPhone { startPreview(c) }
    }

    private func resumePreview() {
        if !playingID.isEmpty, let c = chans.first(where: { $0.s("stream_id") == playingID }) { startPreview(c) }
    }

    private func tapChannel(_ c: JObj) {
        if DeviceInfo.isPhone { openFull(c); return }
        if playingID == c.s("stream_id") && preview.state != .failed { openFull(c); return }
        startPreview(c)
    }

    private func startPreview(_ c: JObj) {
        guard let x = app.xtream else { return }
        playingID = c.s("stream_id")
        preview.playLive(x, id: playingID)
        remember(c)
        Task { epg = await EPG.short(x, id: playingID, limit: 3) }
    }

    private func remember(_ c: JObj) {
        Library.lastLive = ["cat": catID, "sid": c.s("stream_id")]
        var item = c
        item["id"] = c.s("stream_id")
        Library.cwAdd("live", item)
        Library.lastPlay = ["kind": "live", "cat": catID, "sid": c.s("stream_id"), "name": c.s("name"), "icon": c.s("stream_icon"),
                            "list": Array(chans.prefix(400))]
    }

    private func openFull(_ c: JObj) {
        preview.stop()
        playingID = c.s("stream_id")
        remember(c)
        let idx = chans.firstIndex { $0.s("stream_id") == c.s("stream_id") } ?? 0
        player.play(PlayRequest(kind: .live, title: c.s("name"), items: chans, index: idx, catID: catID))
    }
}

/// Guia agora / a seguir
struct EPGNowNext: View {
    let listings: [JObj]
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if listings.isEmpty {
                Text(t("no_epg")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.55))
            }
            ForEach(Array(listings.prefix(3).enumerated()), id: \.offset) { i, l in
                let st = Date(timeIntervalSince1970: l.d("start_timestamp")), en = Date(timeIntervalSince1970: l.d("stop_timestamp"))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(i == 0 ? t("now") : t("next")).font(.system(size: UIScale.small, weight: .bold)).foregroundColor(i == 0 ? app.brand.accent : .white.opacity(0.6))
                        Text(Fmt.hm(st) + " – " + Fmt.hm(en)).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.6))
                    }
                    Text(l.s("title").base64Decoded).font(.system(size: UIScale.body, weight: i == 0 ? .semibold : .regular)).foregroundColor(.white).lineLimit(1)
                    if i == 0 {
                        let total = en.timeIntervalSince(st), done = Date().timeIntervalSince(st)
                        if total > 0 {
                            ProgressView(value: max(0, min(1, done / total))).tint(app.brand.accent)
                        }
                        let desc = l.s("description").base64Decoded
                        if !desc.isEmpty { Text(desc).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.7)).lineLimit(3) }
                    }
                }
            }
        }
    }
}

enum EPG {
    static func short(_ x: Xtream, id: String, limit: Int) async -> [JObj] {
        guard let j = try? await x.call("get_short_epg", ["stream_id": id, "limit": "\(limit)"]) as? JObj else { return [] }
        return j.a("epg_listings")
    }
    /// Programas do canal com o que tem gravado (catch-up)
    static func table(_ x: Xtream, id: String) async -> [JObj] {
        guard let j = try? await x.call("get_simple_data_table", ["stream_id": id]) as? JObj else { return [] }
        return j.a("epg_listings")
    }
}
