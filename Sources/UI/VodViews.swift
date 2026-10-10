import SwiftUI

/// Filmes ou séries: categorias e a grade de capas
struct VodView: View {
    let type: String                // movie | series
    var startCategory: String = ""
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lock = AdultLock.shared

    @State private var cats: [JObj] = []
    @State private var catID = ""
    @State private var items: [JObj] = []
    @State private var loading = true
    @State private var filter = ""
    @State private var askPin: JObj?
    @State private var pin = ""
    @State private var showCats = true   // telas estreitas: categorias → capas

    private var specials: [JObj] {
        [["category_id": SpecialCat.cw, "category_name": t("continue")], ["category_id": SpecialCat.fav, "category_name": "★ " + t("favorites")]]
    }

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > 760
            VStack(spacing: 0) {
                TopBar(title: t(type == "movie" ? "movies" : "series"), onBack: back)
                if wide {
                    HStack(alignment: .top, spacing: UIScale.v(10, 14, 30)) {
                        catList.frame(width: g.size.width * 0.25)
                        grid
                    }
                    .padding(.horizontal, UIScale.pad).padding(.top, 8)
                } else {
                    Group { if showCats && startCategory.isEmpty { catList } else { grid } }
                        .padding(.horizontal, UIScale.pad).padding(.top, 8)
                }
            }
        }
        .task { await load() }
        .alert(t("adult_pin"), isPresented: Binding(get: { askPin != nil }, set: { if !$0 { askPin = nil } })) {
            SecureField(t("adult_pin"), text: $pin)
            Button(t("cancel"), role: .cancel) { pin = "" }
            Button(t("ok")) {
                if lock.check(pin), let c = askPin { Task { await open(c) } } else { app.show(t("pin_wrong")) }
                pin = ""
            }
        }
        #if os(tvOS)
        .onExitCommand { back() }
        #endif
    }

    private func back() {
        if !showCats && startCategory.isEmpty { showCats = true; return }
        dismiss()
    }

    private var catList: some View {
        ScrollView {
            LazyVStack(spacing: UIScale.v(6, 8, 14)) {
                NavigationLink(value: Dest.search) {
                    HStack { Image(systemName: "magnifyingglass"); Text(t("search_go")).font(.system(size: UIScale.body, weight: .medium)); Spacer(minLength: 0) }
                }
                .buttonStyle(RowStyle())
                ForEach(Array((specials + cats).enumerated()), id: \.offset) { _, c in
                    Button { tap(c) } label: {
                        HStack(spacing: 8) {
                            if Config.isAdult(c.s("category_name")) && !lock.unlocked { Image(systemName: "lock.fill") }
                            Text(c.s("category_name")).font(.system(size: UIScale.body, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(RowStyle(selected: catID == c.s("category_id")))
                }
                if loading && cats.isEmpty { Spinner().padding() }
            }
            .padding(.vertical, 6)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var visible: [JObj] {
        let f = filter.trimmed.lowercased()
        return f.isEmpty ? items : items.filter { $0.s("name").lowercased().contains(f) }
    }

    private var grid: some View {
        VStack(spacing: 8) {
            if items.count > 24 {
                TextField(t("filter_ph"), text: $filter).font(.system(size: UIScale.body)).padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))).disableAutocorrection(true)
            }
            ScrollView {
                if loading { Spinner().padding() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: UIScale.poster, maximum: UIScale.poster * 1.4), spacing: UIScale.v(10, 14, 40))],
                          spacing: UIScale.v(12, 16, 50)) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, it in
                        NavigationLink(value: type == "movie" ? Dest.movie(Item(it)) : Dest.show(Item(it))) {
                            PosterCard(item: Item(it), progress: progress(it))
                        }
                        .buttonStyle(TileStyle())
                    }
                }
                .padding(.vertical, UIScale.v(6, 8, 30))
                .padding(.horizontal, UIScale.v(2, 4, 20))
                if !loading && items.isEmpty { EmptyText(text: t(catID == SpecialCat.fav ? "fav_empty" : (catID == SpecialCat.cw ? "cw_none" : "empty"))) }
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func progress(_ it: JObj) -> Double {
        guard type == "movie" else { return 0 }
        let id = it.s("stream_id").isEmpty ? it.s("id") : it.s("stream_id")
        let p = Library.position(movie: id), d = Double(it.s("duration_secs")) ?? 0
        return d > 0 ? p / d : (p > 30 ? 0.05 : 0)
    }

    private func load() async {
        guard let x = app.xtream else { return }
        let l = (try? await x.list(type == "movie" ? "get_vod_categories" : "get_series_categories", playlistID: app.playlistID)) ?? []
        cats = filterCategories(l)
        loading = false
        let first: JObj
        if !startCategory.isEmpty { first = specials.first { $0.s("category_id") == startCategory } ?? specials[1] }
        else if !Library.cwList(type).isEmpty { first = specials[0] }
        else { first = cats.first ?? specials[1] }
        await open(first, move: false)
    }

    private func tap(_ c: JObj) {
        if Config.isAdult(c.s("category_name")) && !lock.unlocked { askPin = c; return }
        Task { await open(c) }
    }

    private func open(_ c: JObj, move: Bool = true) async {
        catID = c.s("category_id"); filter = ""
        if move { showCats = false }
        switch catID {
        case SpecialCat.cw: items = Library.cwList(type)
        case SpecialCat.fav: items = Library.favList(type)
        default:
            guard let x = app.xtream else { return }
            loading = true; items = []
            items = (try? await x.list(type == "movie" ? "get_vod_streams" : "get_series", ["category_id": catID], playlistID: app.playlistID)) ?? []
            loading = false
        }
    }
}

struct PosterCard: View {
    let item: Item
    var progress: Double = 0
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                Color.white.opacity(0.06)
                RemoteImage(url: item.image, placeholder: "film")
                if progress > 0 {
                    GeometryReader { g in
                        Rectangle().fill(app.brand.accent).frame(width: g.size.width * min(1, progress), height: 4).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(width: UIScale.poster, height: UIScale.poster * 1.48)
            .clipShape(RoundedRectangle(cornerRadius: UIScale.v(10, 12, 18)))
            if Prefs.cardTitle {
                Text(item.name).font(.system(size: UIScale.small, weight: .medium)).foregroundColor(.white).lineLimit(2)
                    .frame(width: UIScale.poster, alignment: .leading)
            }
        }
    }
}

// MARK: - Detalhes do filme

struct MovieDetailView: View {
    let item: Item
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @State private var info: JObj = [:]
    @State private var ext = ""
    @State private var fav = false
    @State private var loading = true

    var id: String { item["stream_id"].isEmpty ? item["id"] : item["stream_id"] }

    var body: some View {
        let pos = Library.position(movie: id)
        VStack(spacing: 0) {
            TopBar(title: t("movies"), onBack: { dismiss() })
            ScrollView {
                DetailLayout(cover: info.s("movie_image").isEmpty ? item.image : info.s("movie_image"), backdrop: (info["backdrop_path"] as? [String])?.first ?? "") {
                    Text(item.name).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white)
                    MetaLine(parts: [info.s("releasedate").isEmpty ? info.s("release_date") : info.s("releasedate"), info.s("genre"), info.s("duration"),
                                     info.d("rating") > 0 ? "★ " + String(format: "%.1f", info.d("rating")) : ""])
                    if loading { Spinner() }
                    Text(info.s("plot").isEmpty ? info.s("description") : info.s("plot")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.85))
                    if !info.s("cast").isEmpty { Text(t("cast") + ": " + info.s("cast")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.65)) }
                    if !info.s("director").isEmpty { Text(t("director") + ": " + info.s("director")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.65)) }
                    ActionsRow {
                        if pos > 30 {
                            Button { play(at: pos) } label: { Label(t("resume") + " " + Fmt.time(pos), systemImage: "play.fill") }.buttonStyle(PillStyle(primary: true))
                            Button { play(at: 0) } label: { Label(t("from_start"), systemImage: "backward.end.fill") }.buttonStyle(PillStyle())
                        } else {
                            Button { play(at: 0) } label: { Label(t("play"), systemImage: "play.fill") }.buttonStyle(PillStyle(primary: true))
                        }
                        Button { fav = Library.toggleFav("movie", item.raw.merging(["container_extension": ext]) { $1 }); app.show(t(fav ? "fav_added" : "fav_removed")) } label: {
                            Label(t(fav ? "fav_del" : "fav_add"), systemImage: fav ? "star.fill" : "star")
                        }.buttonStyle(PillStyle())
                        #if os(iOS)
                        if !info.s("youtube_trailer").isEmpty, let u = URL(string: "https://www.youtube.com/watch?v=" + info.s("youtube_trailer")) {
                            Link(destination: u) { Label(t("trailer"), systemImage: "play.rectangle") }.buttonStyle(PillStyle())
                        }
                        #endif
                    }
                }
            }
        }
        .task {
            fav = Library.isFav("movie", item.raw)
            ext = item["container_extension"]
            guard let x = app.xtream, let j = try? await x.call("get_vod_info", ["vod_id": id]) as? JObj else { loading = false; return }
            info = j.o("info")
            if !j.o("movie_data").s("container_extension").isEmpty { ext = j.o("movie_data").s("container_extension") }
            loading = false
        }
    }

    private func play(at: Double) {
        let it: JObj = ["stream_id": id, "name": item.name, "stream_icon": item.image, "container_extension": ext.isEmpty ? "mp4" : ext,
                        "duration_secs": info.s("duration_secs")]
        player.play(PlayRequest(kind: .movie, title: item.name, item: it, startAt: at))
    }
}

// MARK: - Detalhes da série

struct SeriesDetailView: View {
    let item: Item
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @State private var info: JObj = [:]
    @State private var episodes: [String: [JObj]] = [:]
    @State private var seasons: [String] = []
    @State private var season = ""
    @State private var fav = false
    @State private var loading = true

    var sid: String { item["series_id"].isEmpty ? item["id"] : item["series_id"] }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("series"), onBack: { dismiss() })
            ScrollView {
                DetailLayout(cover: item.image.isEmpty ? info.s("cover") : item.image, backdrop: (info["backdrop_path"] as? [String])?.first ?? "") {
                    Text(item.name).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white)
                    MetaLine(parts: [info.s("releaseDate"), info.s("genre"), info.d("rating") > 0 ? "★ " + String(format: "%.1f", info.d("rating")) : ""])
                    Text(info.s("plot")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.85)).lineLimit(6)
                    ActionsRow {
                        if let next = nextEpisode {
                            Button { play(next.0, next.1) } label: { Label(t("continue") , systemImage: "play.fill") }.buttonStyle(PillStyle(primary: true))
                        }
                        Button { fav = Library.toggleFav("series", ["series_id": sid, "name": item.name, "cover": item.image]); app.show(t(fav ? "fav_added" : "fav_removed")) } label: {
                            Label(t(fav ? "fav_del" : "fav_add"), systemImage: fav ? "star.fill" : "star")
                        }.buttonStyle(PillStyle())
                    }
                    if loading { Spinner() }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(seasons, id: \.self) { s in
                                Button { season = s } label: {
                                    Text(t("season") + " " + s).font(.system(size: UIScale.small, weight: .semibold))
                                        .padding(.horizontal, 14).padding(.vertical, UIScale.v(8, 9, 14))
                                        .background(Capsule().fill(season == s ? app.brand.accent.opacity(0.85) : Color.white.opacity(0.1)))
                                        .foregroundColor(season == s && app.brand.accentIsLight ? .black : .white)
                                }
                                .buttonStyle(TileStyle(radius: 30))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                    LazyVStack(spacing: UIScale.v(6, 8, 14)) {
                        ForEach(Array((episodes[season] ?? []).enumerated()), id: \.offset) { i, ep in
                            let p = Library.position(episode: ep.s("id"))
                            Button { play(season, i) } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(url: ep.o("info").s("movie_image"), placeholder: "play.rectangle").frame(width: UIScale.v(70, 90, 160), height: UIScale.v(40, 50, 90)).clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(ep.s("episode_num").isEmpty ? "\(i + 1)" : ep.s("episode_num")). " + ep.s("title")).font(.system(size: UIScale.body, weight: .medium)).lineLimit(1)
                                        if !ep.o("info").s("duration").isEmpty { Text(ep.o("info").s("duration")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.6)) }
                                    }
                                    Spacer(minLength: 0)
                                    if p > 30 { Text(Fmt.time(p)).font(.system(size: UIScale.small, weight: .bold)).foregroundColor(app.brand.accent) }
                                }
                            }
                            .buttonStyle(RowStyle())
                        }
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
        }
        .task {
            fav = Library.isFav("series", ["series_id": sid])
            guard let x = app.xtream, let j = try? await x.call("get_series_info", ["series_id": sid]) as? JObj else { loading = false; return }
            info = j.o("info")
            var eps: [String: [JObj]] = [:]
            if let d = j["episodes"] as? [String: Any] {
                for (k, v) in d { if let arr = v as? [JObj] { eps[k] = arr } }
            } else if let arr = j["episodes"] as? [[JObj]] {
                for a in arr { if let s = a.first?.s("season") { eps[s] = a } }
            }
            episodes = eps
            seasons = eps.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            // abre na temporada do último episódio assistido
            let lastEp = Library.cwList("series").first { $0.s("id") == sid }?.s("last_season") ?? ""
            season = seasons.contains(lastEp) ? lastEp : (seasons.first ?? "")
            loading = false
        }
    }

    /// Último episódio assistido desta série (para o botão Continuar)
    private var nextEpisode: (String, Int)? {
        guard let cw = Library.cwList("series").first(where: { $0.s("id") == sid }) else { return nil }
        let s = cw.s("last_season"), eid = cw.s("last_episode")
        guard let i = episodes[s]?.firstIndex(where: { $0.s("id") == eid }) else { return nil }
        return (s, i)
    }

    private func play(_ s: String, _ i: Int) {
        guard let eps = episodes[s], i < eps.count else { return }
        let ep = eps[i]
        let p = Library.position(episode: ep.s("id"))
        let series: JObj = ["series_id": sid, "name": item.name, "cover": item.image]
        player.play(PlayRequest(kind: .episode, title: item.name + " – " + ep.s("title"), items: eps, index: i, series: series.merging(["season": s]) { $1 }, startAt: p > 30 ? p : 0))
    }
}

/// Capa à esquerda e informações à direita (deitado) ou uma embaixo da outra (em pé)
struct DetailLayout<Content: View>: View {
    let cover: String
    let backdrop: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack(alignment: .top) {
            if !backdrop.isEmpty {
                RemoteImage(url: backdrop, placeholder: "").frame(height: UIScale.v(220, 360, 600)).clipped().opacity(0.35)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: UIScale.v(16, 26, 60)) {
                    coverView
                    VStack(alignment: .leading, spacing: UIScale.v(10, 12, 22)) { content() }.frame(minWidth: 420, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    coverView.frame(maxWidth: .infinity)
                    content()
                }
            }
            .padding(UIScale.pad)
        }
    }
    private var coverView: some View {
        RemoteImage(url: cover, placeholder: "film")
            .frame(width: UIScale.v(160, 240, 400), height: UIScale.v(236, 355, 590))
            .clipShape(RoundedRectangle(cornerRadius: UIScale.v(12, 14, 20)))
            .background(RoundedRectangle(cornerRadius: UIScale.v(12, 14, 20)).fill(Color.white.opacity(0.06)))
    }
}

struct MetaLine: View {
    let parts: [String]
    var body: some View {
        let p = parts.map { $0.trimmed }.filter { !$0.isEmpty }
        if !p.isEmpty { Text(p.joined(separator: "  ·  ")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.7)) }
    }
}

struct ActionsRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: UIScale.v(8, 12, 24)) { content() }
            VStack(alignment: .leading, spacing: 10) { content() }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}
