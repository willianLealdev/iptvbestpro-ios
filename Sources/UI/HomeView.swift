import SwiftUI

/// Telas que abrem a partir da tela inicial
enum Dest: Hashable {
    case live
    case movies
    case series
    case search
    case favorites
    case cont
    case settings
    case playlists
    case guide
    case movie(Item)
    case show(Item)
    case vodFav(String)   // movie | series
}

enum HomeAction: String {
    case live, movies, series, cont, search, fav, playlist, settings, refresh, support, multi, guide

    var icon: String {
        switch self {
        case .live: return "tv"
        case .movies: return "film"
        case .series: return "play.rectangle.on.rectangle"
        case .cont: return "play.fill"
        case .search: return "magnifyingglass"
        case .fav: return "star.fill"
        case .playlist: return "list.bullet"
        case .settings: return "gearshape.fill"
        case .refresh: return "arrow.clockwise"
        case .support: return "message.fill"
        case .multi: return "square.grid.2x2.fill"
        case .guide: return "calendar"
        }
    }
    var label: String {
        switch self {
        case .live: return t("live")
        case .movies: return t("movies")
        case .series: return t("series")
        case .cont: return t("cont_tile")
        case .search: return t("search")
        case .fav: return t("favorites")
        case .playlist: return t("playlist")
        case .settings: return t("settings")
        case .refresh: return t("refresh")
        case .support: return t("support")
        case .multi: return t("multi")
        case .guide: return t("guide")
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @State private var path: [Dest] = []
    @State private var showSupport = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                TopBar(trailing: {
                    HStack(spacing: UIScale.v(4, 8, 14)) {
                        ForEach([HomeAction.search, .guide, .multi, .refresh, .support], id: \.self) { a in
                            Button { run(a) } label: {
                                Image(systemName: a.icon).font(.system(size: UIScale.v(17, 20, 32), weight: .semibold))
                                    .frame(width: UIScale.v(36, 42, 76), height: UIScale.v(36, 42, 76))
                                    .background(Circle().fill(Color.white.opacity(0.1)))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(TileStyle(radius: 40))
                            .accessibilityLabel(a.label)
                        }
                    }
                })
                ThemeHome(run: run)
            }
            .screen()
            .navigationDestination(for: Dest.self) { d in destination(d).screen() }
        }
        .onAppear {
            app.homeAppeared()
            #if DEBUG
            if let sc = app.debugScreen, path.isEmpty, let a = HomeAction(rawValue: sc) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { run(a) }
            }
            #endif
        }
        .onChange(of: path.count) { n in
            app.homeVisible = n == 0
            if n == 0 { app.homeAppeared() }
        }
        .sheet(isPresented: $showSupport) { SupportSheet() }
        .sheet(item: Binding(get: { app.expiryNotice.map { ExpiryBox(days: $0) } }, set: { app.expiryNotice = $0?.days })) { b in
            ExpirySheet(days: b.days)
        }
    }

    func run(_ a: HomeAction) {
        Prefs.set("bp_home", a.rawValue)
        switch a {
        case .live: path.append(.live)
        case .movies: path.append(.movies)
        case .series: path.append(.series)
        case .search: path.append(.search)
        case .fav: path.append(.favorites)
        case .playlist: path.append(.playlists)
        case .settings: path.append(.settings)
        case .guide: path.append(.guide)
        case .cont: continueLast()
        case .refresh: Task { await app.refreshAll() }
        case .support: showSupport = true
        case .multi: player.multiscreen = true
        }
    }

    /// Botão "Continuar": abre direto o último canal, filme ou episódio assistido
    private func continueLast() {
        guard let o = Library.lastPlay else { app.show(t("cw_empty"), seconds: 5); return }
        switch o.s("kind") {
        case "live":
            let list = (o["list"] as? [JObj]) ?? [["stream_id": o.s("sid"), "name": o.s("name"), "stream_icon": o.s("icon")]]
            let idx = list.firstIndex { $0.s("stream_id") == o.s("sid") } ?? 0
            player.play(PlayRequest(kind: .live, title: o.s("name"), items: list, index: idx, catID: o.s("cat")))
        case "movie":
            let it: JObj = ["stream_id": o.s("id"), "name": o.s("name"), "stream_icon": o.s("icon"), "container_extension": o.s("ext")]
            player.play(PlayRequest(kind: .movie, title: o.s("name"), item: it, startAt: Library.position(movie: o.s("id"))))
        case "series":
            let eps = (o["episodes"] as? [JObj]) ?? [["id": o.s("id"), "title": o.s("title"), "container_extension": o.s("ext")]]
            let idx = eps.firstIndex { $0.s("id") == o.s("id") } ?? 0
            player.play(PlayRequest(kind: .episode, title: o.s("title"), items: eps, index: idx, series: o.o("series"), startAt: Library.position(episode: o.s("id"))))
        default:
            app.show(t("cw_empty"), seconds: 5)
        }
    }

    @ViewBuilder func destination(_ d: Dest) -> some View {
        switch d {
        case .live: LiveView()
        case .movies: VodView(type: "movie")
        case .series: VodView(type: "series")
        case .search: SearchView()
        case .favorites: FavoritesView()
        case .cont: FavoritesView(continueMode: true)
        case .settings: SettingsView()
        case .playlists: PlaylistsView()
        case .guide: GuideView()
        case .movie(let it): MovieDetailView(item: it)
        case .show(let it): SeriesDetailView(item: it)
        case .vodFav(let type): VodView(type: type, startCategory: "_fav")
        }
    }
}

struct ExpiryBox: Identifiable { let days: Int; var id: Int { days } }

// MARK: - Temas da tela inicial

struct TileCfg {
    enum Style { case card, grad, round, btn, wide }
    var style: Style = .card
    var c1: Color = Color(white: 0.15)
    var c2: Color?
    var alpha: Double = 1
    var ring: Color?
    var bar: Color?
    var icon: String = ""
    var iconColor: Color = .white
    var iconCircle: Color?
    var iconScale: CGFloat = 1     // relativo ao lado menor do cartão
    var img: String = ""           // imagem decorativa do tema no lugar do ícone (Halloween)
    var decor: String = ""         // imagem decorativa extra (Natal)
    var decorRect: CGRect = .zero  // posição da decoração (fração do cartão)
    var pattern = false
    var labelScale: CGFloat = 1
}

struct TileSpec: Identifiable {
    let id = UUID()
    var rect: CGRect               // em pixels da tela de 1920x1080 (igual aos apps de TV)
    var action: HomeAction?
    var cfg: TileCfg
    var label: String { action?.label ?? "" }
}

enum Themes {
    static func specs(_ b: Brand) -> [TileSpec] {
        func c(_ k: String, _ d: String) -> Color { b.color(k, d) }
        switch b.themeID {
        case "1":
            // OneUI: TV ao vivo grande à esquerda, Filmes e Séries ao lado, botões embaixo
            let pat = b.on("show_pattern")
            var l: [TileSpec] = [
                TileSpec(rect: CGRect(x: 60, y: 160, width: 640, height: 760), action: .live, cfg: TileCfg(style: .grad, c1: c("live_bottom", "#3C56DE"), c2: c("live_top", "#36D29B"), icon: "tv", iconScale: 0.32, pattern: pat, labelScale: 1.35)),
                TileSpec(rect: CGRect(x: 730, y: 160, width: 555, height: 560), action: .movies, cfg: TileCfg(style: .grad, c1: c("movies_bottom", "#F69D3F"), c2: c("movies_top", "#DB2E54"), icon: "film", iconScale: 0.3, pattern: pat, labelScale: 1.15)),
                TileSpec(rect: CGRect(x: 1305, y: 160, width: 555, height: 560), action: .series, cfg: TileCfg(style: .grad, c1: c("series_bottom", "#5396DC"), c2: c("series_top", "#9C3CB3"), icon: "play.rectangle.on.rectangle", iconScale: 0.3, pattern: pat, labelScale: 1.15)),
            ]
            let btn = c("buttons", "#4DB6AC"), xs: [CGFloat] = [730, 1017, 1304, 1591]
            let acts: [HomeAction] = [.cont, .fav, .playlist, .settings]
            for i in 0..<4 { l.append(TileSpec(rect: CGRect(x: xs[i], y: 750, width: 269, height: 170), action: acts[i], cfg: TileCfg(style: .card, c1: btn, icon: acts[i].icon, iconScale: 0.3, labelScale: 0.7))) }
            return l
        case "2":
            // Glossy: botões redondos à esquerda, menu no meio, TV/Filmes/Séries com borda colorida à direita
            let a1 = c("accent_start", "#FD4C3A"), a2 = c("accent_end", "#FF7439"), p1 = c("panel_top", "#233245"), p2 = c("panel_bottom", "#141A26")
            let p2hex = b.ms.s("panel_bottom").isEmpty ? "#141A26" : b.ms.s("panel_bottom")
            var l: [TileSpec] = []
            let rb: [HomeAction] = [.settings, .playlist, .refresh, .support]
            for (r, a) in rb.enumerated() { l.append(TileSpec(rect: CGRect(x: 60, y: 170 + CGFloat(r) * 160, width: 120, height: 120), action: a, cfg: TileCfg(style: .round, c1: a1, c2: a2, icon: a.icon, iconScale: 0.45))) }
            l.append(TileSpec(rect: CGRect(x: 230, y: 160, width: 560, height: 760), action: nil, cfg: TileCfg(style: .grad, c1: p2, c2: p1)))
            let mid: [HomeAction] = [.fav, .search, .cont]
            for (q, a) in mid.enumerated() { l.append(TileSpec(rect: CGRect(x: 260, y: 190 + CGFloat(q) * 240, width: 500, height: 220), action: a, cfg: TileCfg(style: .btn, c1: Color.mix(p2hex, 0.06), icon: a.icon, iconScale: 0.3, labelScale: 0.85))) }
            let big: [HomeAction] = [.live, .movies, .series]
            for (g, a) in big.enumerated() { l.append(TileSpec(rect: CGRect(x: 830, y: 160 + CGFloat(g) * 265, width: 1030, height: 230), action: a, cfg: TileCfg(style: .wide, c1: p2, ring: a1, icon: a.icon, iconScale: 0.5, labelScale: 1.3))) }
            return l
        case "3":
            // Black Panther: cartões cinza com o ícone num círculo e botões com faixa
            let ac = c("accent", "#E22F4D"), cd = c("card", "#404040")
            var l: [TileSpec] = []
            let big: [HomeAction] = [.live, .movies, .series]
            for (i, a) in big.enumerated() { l.append(TileSpec(rect: CGRect(x: 100 + CGFloat(i) * 600, y: 170, width: 520, height: 440), action: a, cfg: TileCfg(style: .card, c1: cd, ring: Color.white.opacity(0.19), icon: a.icon, iconCircle: ac, iconScale: 0.2, labelScale: 1.1))) }
            let small: [HomeAction] = [.cont, .fav, .playlist, .settings]
            for (i, a) in small.enumerated() { l.append(TileSpec(rect: CGRect(x: 100 + CGFloat(i) * 440, y: 680, width: 400, height: 130), action: a, cfg: TileCfg(style: .btn, c1: cd, bar: ac, icon: a.icon, iconScale: 0.4, labelScale: 0.75))) }
            return l
        case "4":
            // MovieUI: pôster em tela cheia e a fila de cartões embaixo
            let tcol = b.ms.s("tile_auto") == "0" ? c("tile_color", "#3A0A10") : Color(hex: "#3A0A10")!
            let row: [HomeAction] = [.live, .movies, .series, .cont, .fav, .playlist, .settings]
            return row.enumerated().map { (i, a) in TileSpec(rect: CGRect(x: 70 + CGFloat(i) * 255, y: 760, width: 240, height: 200), action: a, cfg: TileCfg(style: .card, c1: tcol, alpha: 0.92, icon: a.icon, iconScale: 0.34, labelScale: 0.62)) }
        case "5", "6", "7":
            // VUI, Natal e Halloween: 3 cartões altos e botões à direita
            let id = b.themeID
            let cols = id == "7" ? [c("live_color", "#FF811D"), c("movies_color", "#7761D5"), c("series_color", "#00C853")]
                                 : [c("live_color", "#E62E2F"), c("movies_color", "#00E676"), c("series_color", "#FF9100")]
            let topHex = !b.ms.s("bg_top").isEmpty ? b.ms.s("bg_top") : (!b.ms.s("bg").isEmpty ? b.ms.s("bg") : "#070923")
            let cd = Color.mix(topHex, 0.07), pat = b.on("show_pattern"), decor = b.on("show_decor")
            let big: [HomeAction] = [.live, .movies, .series]
            let imgs = ["hw_pumpkin", "hw_bat", "hw_cauldron"]
            let xm: [(String, CGRect)] = [("xmas_santa", CGRect(x: -0.05, y: 0.68, width: 0.59, height: 0.3)), ("xmas_balls", CGRect(x: 0.12, y: -0.01, width: 0.77, height: 0.39)), ("xmas_snowman", CGRect(x: 0.49, y: 0.71, width: 0.54, height: 0.28))]
            var l: [TileSpec] = []
            for (v, a) in big.enumerated() {
                var cfg = TileCfg(style: .card, c1: cd, ring: Color.white.opacity(0.08), icon: a.icon, iconColor: cols[v], iconScale: 0.42, pattern: pat, labelScale: 1.35)
                if id == "7" && decor { cfg.img = imgs[v]; cfg.iconScale = 0.66 }
                if id == "6" && decor { cfg.decor = xm[v].0; cfg.decorRect = xm[v].1 }
                l.append(TileSpec(rect: CGRect(x: 60 + CGFloat(v) * 420, y: 160, width: 390, height: 760), action: a, cfg: cfg))
            }
            let side: [HomeAction] = [.cont, .fav, .playlist, .settings]
            let hwi = ["", "hw_ghost", "hw_candy", "hw_candycorn"]
            for (sd, a) in side.enumerated() {
                var cfg = TileCfg(style: .btn, c1: cd, ring: Color.white.opacity(0.08), icon: a.icon, iconScale: 0.32, labelScale: 0.8)
                if id == "7" && decor && !hwi[sd].isEmpty { cfg.img = hwi[sd] }
                l.append(TileSpec(rect: CGRect(x: 1320, y: 160 + CGFloat(sd) * 195, width: 540, height: 175), action: a, cfg: cfg))
            }
            return l
        default:
            // BestPro (padrão): banner da marca, 3 cartões grandes e os botões embaixo
            let card = b.card, acc = b.accent
            var l: [TileSpec] = []
            let big: [HomeAction] = [.live, .movies, .series]
            for (i, a) in big.enumerated() {
                let col = [b.colorOpt(["live_top", "live_color"]), b.colorOpt(["movies_top", "movies_color"]), b.colorOpt(["series_top", "series_color"])][i]
                l.append(TileSpec(rect: CGRect(x: 80 + CGFloat(i) * 600, y: 420, width: 560, height: 300), action: a, cfg: TileCfg(style: .card, c1: col ?? card, alpha: 0.92, icon: a.icon, iconColor: col == nil ? acc : .white, iconScale: 0.36, labelScale: 1.1)))
            }
            let mini: [HomeAction] = [.cont, .search, .fav, .playlist, .settings]
            for (i, a) in mini.enumerated() { l.append(TileSpec(rect: CGRect(x: 80 + CGFloat(i) * 357, y: 760, width: 330, height: 170), action: a, cfg: TileCfg(style: .card, c1: card, alpha: 0.9, icon: a.icon, iconScale: 0.3, labelScale: 0.7))) }
            return l
        }
    }
}

/// Monta o tema: no formato deitado (TV, iPad, iPhone deitado) usa as mesmas posições dos apps de TV;
/// em pé (iPhone/iPad em pé) empilha os mesmos cartões, com as mesmas cores do tema.
struct ThemeHome: View {
    @EnvironmentObject var app: AppState
    let run: (HomeAction) -> Void

    var body: some View {
        let specs = Themes.specs(app.brand)
        GeometryReader { g in
            let landscape = g.size.width > g.size.height * 1.15
            ZStack(alignment: .topLeading) {
                if app.brand.themeID == "6" && app.brand.on("show_snow") { SnowView().allowsHitTesting(false) }
                if landscape { canvas(specs, g.size) } else { portrait(specs, g.size) }
            }
        }
        .padding(.bottom, UIScale.v(6, 10, 30))
    }

    // Deitado: posições da tela de 1920x1080 (faixa de y 150...980 vira a área disponível)
    private func canvas(_ specs: [TileSpec], _ size: CGSize) -> some View {
        let hasBanner = app.brand.themeID == "8" || !["1", "2", "3", "4", "5", "6", "7"].contains(app.brand.themeID)
        let sx = size.width / 1920, sy = size.height / 830
        return ZStack(alignment: .topLeading) {
            if hasBanner {
                RemoteImage(url: app.brand.banner.isEmpty ? app.brand.logo : app.brand.banner, fill: false, placeholder: "")
                    .frame(width: size.width * 0.6, height: 230 * sy).position(x: size.width / 2, y: 135 * sy)
            }
            if app.brand.themeID == "7" && app.brand.on("show_decor") {
                RemoteImage(url: Config.server + "/tv/img/hw_web.png", fill: false, placeholder: "").frame(width: 300 * sx, height: 300 * sx).opacity(0.18)
                    .position(x: 1710 * sx, y: (1010 - 150) * sy)
                RemoteImage(url: Config.server + "/tv/img/hw_spider.png", fill: false, placeholder: "").frame(width: 110 * sx, height: 110 * sx).opacity(0.55)
                    .position(x: 1280 * sx, y: max(10, (185 - 150) * sy))
            }
            ForEach(specs) { sp in
                let r = CGRect(x: sp.rect.minX * sx, y: (sp.rect.minY - 150) * sy, width: sp.rect.width * sx, height: sp.rect.height * sy)
                tile(sp, r.size).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // Em pé: cartões grandes primeiro, depois os botões em grade
    private func portrait(_ specs: [TileSpec], _ size: CGSize) -> some View {
        let big = specs.filter { [.live, .movies, .series].contains($0.action) }
        let small = specs.filter { $0.action != nil && ![.live, .movies, .series].contains($0.action) }
        let gap: CGFloat = 12, w = size.width - UIScale.pad * 2
        return ScrollView {
            VStack(spacing: gap) {
                if app.brand.themeID == "8" || app.brand.themeID.isEmpty {
                    RemoteImage(url: app.brand.banner.isEmpty ? app.brand.logo : app.brand.banner, fill: false, placeholder: "").frame(height: min(150, size.height * 0.18))
                }
                if let first = big.first { tile(first, CGSize(width: w, height: w * 0.48)).frame(width: w, height: w * 0.48) }
                HStack(spacing: gap) {
                    ForEach(big.dropFirst()) { sp in tile(sp, CGSize(width: (w - gap) / 2, height: w * 0.4)).frame(width: (w - gap) / 2, height: w * 0.4) }
                }
                let cols = Array(repeating: GridItem(.flexible(), spacing: gap), count: UIScale.phone ? 2 : 3)
                LazyVGrid(columns: cols, spacing: gap) {
                    ForEach(small) { sp in
                        tile(Self.flat(sp), CGSize(width: w / 2, height: 86)).frame(height: 86)
                    }
                }
            }
            .padding(.horizontal, UIScale.pad).padding(.top, 8)
        }
    }

    /// Em pé os botões redondos (Glossy) viram cartões
    static func flat(_ sp: TileSpec) -> TileSpec {
        var s = sp
        if s.cfg.style == .round { s.cfg.style = .card; s.cfg.iconScale = 0.3 }
        return s
    }

    @ViewBuilder private func tile(_ sp: TileSpec, _ size: CGSize) -> some View {
        if let a = sp.action {
            Button { run(a) } label: { HomeTile(spec: sp, size: size) }
                .buttonStyle(TileStyle(radius: sp.cfg.style == .round ? size.width : UIScale.v(14, 16, 22)))
                .accessibilityLabel(sp.label)
        } else {
            HomeTile(spec: sp, size: size)
        }
    }
}

struct HomeTile: View {
    let spec: TileSpec
    let size: CGSize
    @EnvironmentObject var app: AppState

    var body: some View {
        let c = spec.cfg
        let side = min(size.width, size.height)
        let radius: CGFloat = c.style == .round ? side : UIScale.v(14, 16, 22)
        let iconSize = max(16, side * c.iconScale)
        let fontSize = max(UIScale.v(11, 13, 24), min(side * 0.13, size.width * 0.075) * c.labelScale)
        ZStack {
            // fundo
            if let c2 = c.c2 {
                LinearGradient(colors: [c2, c.c1], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                c.c1.opacity(c.alpha)
            }
            if c.pattern { PatternOverlay() }
            // conteúdo
            Group {
                switch c.style {
                case .round:
                    icon(iconSize)
                case .btn:
                    HStack(spacing: side * 0.16) {
                        icon(iconSize)
                        label(fontSize)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, side * 0.22)
                case .wide:
                    HStack {
                        label(fontSize)
                        Spacer()
                        icon(iconSize)
                    }
                    .padding(.horizontal, side * 0.3)
                default:
                    VStack(spacing: side * 0.07) {
                        icon(iconSize)
                        label(fontSize)
                    }
                    .padding(8)
                }
            }
            if !c.decor.isEmpty {
                GeometryReader { g in
                    RemoteImage(url: Config.server + "/tv/img/\(c.decor).png", fill: false, placeholder: "")
                        .frame(width: g.size.width * c.decorRect.width, height: g.size.width * c.decorRect.width)
                        .position(x: g.size.width * (c.decorRect.minX + c.decorRect.width / 2), y: g.size.height * (c.decorRect.minY + c.decorRect.height / 2))
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(c.ring ?? .clear, lineWidth: c.style == .wide ? 4 : 2))
        .overlay(alignment: .leading) {
            if let bar = c.bar { Rectangle().fill(bar).frame(width: max(5, side * 0.09)).clipShape(RoundedRectangle(cornerRadius: 3)) }
        }
    }

    @ViewBuilder private func icon(_ s: CGFloat) -> some View {
        let c = spec.cfg
        let inner: AnyView = c.img.isEmpty
            ? AnyView(Image(systemName: c.icon).font(.system(size: s * 0.8, weight: .semibold)).foregroundColor(c.iconColor).frame(width: s, height: s))
            : AnyView(RemoteImage(url: Config.server + "/tv/img/\(c.img).png", fill: false, placeholder: c.icon).frame(width: s, height: s))
        if let circle = c.iconCircle {
            inner.frame(width: s * 1.75, height: s * 1.75).background(Circle().fill(circle))
        } else {
            inner
        }
    }

    private func label(_ f: CGFloat) -> some View {
        Text(spec.label).font(.system(size: f, weight: .heavy)).foregroundColor(app.brand.text)
            .lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// Textura leve dos cartões (OneUI, VUI)
struct PatternOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 26
            var y: CGFloat = 0
            while y < size.height + step {
                var x: CGFloat = (Int(y / step) % 2 == 0) ? 0 : step / 2
                while x < size.width + step {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(0.08)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

/// Neve caindo (tema Natal, opção do painel)
struct SnowView: View {
    private let flakes: [(CGFloat, CGFloat, Double, Double)] = (0..<34).map { _ in
        (CGFloat.random(in: 0...1), CGFloat.random(in: 4...11), Double.random(in: 9...19), Double.random(in: 0...19))
    }
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSinceReferenceDate
                for f in flakes {
                    let p = ((now + f.3).truncatingRemainder(dividingBy: f.2)) / f.2
                    let x = f.0 * size.width + sin(p * .pi * 4) * 14
                    let y = p * (size.height + 20) - 10
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: f.1, height: f.1)), with: .color(.white.opacity(0.65)))
                }
            }
        }
    }
}

// MARK: - Suporte e aviso de vencimento

struct SupportSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            BrandBackground()
            ScrollView {
                CardBox {
                    Text(t("support")).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white)
                    SupportContact()
                    DeviceIDBox()
                    Button(t("close")) { dismiss() }.buttonStyle(PillStyle())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }
}

struct ExpirySheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let days: Int
    @State private var error = ""
    var body: some View {
        ZStack {
            BrandBackground()
            ScrollView {
                CardBox {
                    Text(t("exp_title")).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                    Text(days <= 0 ? t("exp_today") : t("exp_days", "\(days)")).font(.system(size: UIScale.body)).foregroundColor(.white)
                    Text(t(app.isReseller ? "exp_reseller" : "exp_support")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.8)).multilineTextAlignment(.center)
                    SupportContact(compact: true)
                    // cliente direto renova pela Apple; cliente de revenda renova com a revenda
                    if app.canPurchase { PurchaseBox(error: $error) }
                    if !error.isEmpty { Text(error).foregroundColor(.orange).font(.system(size: UIScale.small)) }
                    Button(t("close")) { dismiss() }.buttonStyle(PillStyle())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }
}

extension View {
    /// Fundo do tema e sem a barra de navegação do sistema (cada tela tem o próprio topo)
    func screen() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(BrandBackground())
            .navigationBarHidden(true)
    }
}
